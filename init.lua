--[[ gpio/timer初始化 ]]
LED_STA = 1			-- STA模式指示灯
LED_STAAP = 2		-- STAAP模式指示灯
LED_SIGN = 4		-- 指示灯
KEY_CONFIG = 3		-- 切换STA/STAAP模式按键
TMR_MAINLOOP = 1	-- 主循环定时器
TMR_SERVER = 4		-- Server定时器
TMR_CONNECT = 5		-- wifi连接定时器
TMR_KEY = 6			-- 防抖延时定时器

gpio.mode(LED_STA, gpio.OUTPUT)
gpio.mode(LED_STAAP, gpio.OUTPUT)
gpio.mode(LED_SIGN, gpio.OUTPUT)
gpio.mode(KEY_CONFIG, gpio.INT)


--[[ 数据初始化 ]]
datafile = 'data.json'	-- 数据保存文件
data = {}				-- 系统数据
date_ = nil				-- 系统时间
ip = nil				-- STA模式ip
wifistatus = 0			-- wifi.sta.status()
wifistatus_ = 0			-- wifi状态旧值

--[[ 配置数据 ]]
function setData(data_)
	if not(type(data_) == "table") then return end
	-- 系统时间
	data.date = (data_.date or date_ or data.date or 0)-0
	-- wifi模式
	data.wifimode = (data_.wifimode or data.wifimode or wifi.STATIONAP)-0
	-- wifi名称
	data.ssid = data_.ssid ~= '' and data_.ssid or data.ssid or 'ssid'
	-- wifi密码
	data.password = data_.password or data.password or 'password'
	-- 远程服务器
	data.remote = data_.remote ~= '' and data_.remote or data.remote or 'http://tuziel.com/demo/nodemcu/'
	-- 插口数量
	data.socketcount = (data_.socketcount or data.socketcount or 1)-0
	-- 插口数据
	if(data_.socket or not data.socket) then
		data.socket = {}
		for i=1, data.socketcount do
			local socket_ = data_.socket and data_.socket[i]
			local plans_ = socket_ and socket_.plans
			data.socket[i] = {
				name = socket_ and socket_.name ~= '' and socket_.name or 'socket'..i,
				pin = 4+i,
				status = (socket_ and socket_.status or 1)-0,
				plans = {}
			}
			-- 插口任务表
			if(plans_ and plans_[1]) then
				for j=1, #plans_ do
					data.socket[i].plans[j] = {}
					data.socket[i].plans[j].time = (plans_[j].time or 0)-0
					data.socket[i].plans[j].case = (plans_[j].case or 1)-0
					data.socket[i].plans[j].isdaily = (plans_[j].isdaily or 0)-0
				end
			end
		end
	end
	date_ = data.date
	saveData(datafile)
end

-- 读取数据文件
function loadData(filename)
	local data_

	file.open(filename)
	data_ = file.read()
	file.close()
	print('loading ' .. filename .. ' Complete')

	return cjson.decode(data_)
end

-- 保存数据文件
function saveData(filename)
	local data_
	data_ = cjson.encode(data)

	file.open(filename, 'w')
	file.write(data_)
	file.close()
	print('saved ' .. filename .. ' Complete')
end


--[[ 切换STA/STAAP模式 ]]
-- STA模式连接wifi
function staConnect()
	ip = wifi.sta.getip()
	if not(ip) then
		wifi.sta.config(data.ssid, data.password)
		print('connecting...')
		tmr.alarm(TMR_CONNECT, 1000, 1, function()
			ip = wifi.sta.getip()
			if ip then
				print(ip)
				dateSyn()
				tmr.unregister(TMR_CONNECT)
			end
		end)
	end
end

-- 设置STA模式
function setSta()
	gpio.write(LED_STAAP, gpio.LOW)
	gpio.write(LED_STA, gpio.HIGH)
	wifi.setmode(wifi.STATION)
	setData( {wifimode = wifi.STATION} )

	staConnect()
end

-- 设置STAAP模式
function setStaap()
	gpio.write(LED_STA, gpio.LOW)
	gpio.write(LED_STAAP, gpio.HIGH)
	wifi.setmode(wifi.STATIONAP)
	setData( {wifimode = wifi.STATIONAP} )

	staConnect()
	wifi.ap.config( {ssid = 'nodemcu', auth = wifi.OPEN} )
	wifi.ap.setip( {ip = "192.168.1.1", netmask = "255.255.255.0", gateway = "192.168.1.1"} )
end

-- 按键切换模式
function changeMode()
	-- 防抖延时
	gpio.trig(KEY_CONFIG)
	tmr.alarm(TMR_KEY, 500, tmr.ALARM_SINGLE, function()
		gpio.trig(KEY_CONFIG, 'down', changeMode)
	end)

	if(data.wifimode ~= wifi.STATIONAP) then
		setStaap()
	else
		setSta()
	end
end
gpio.trig(KEY_CONFIG, 'down', changeMode)


--[[ 远程时钟同步 ]]
function dateSyn()
	http.get(data.remote .. 'time.php', nil, function(code, data_)
		if(code == 200) then
			setData( {date = data_} )
		end
	end)
end


--[[ 处理任务计划 ]]
function checkPlans()
	for i=1, data.socketcount do
		local socket_ = data.socket[i]
		local del = {}
		for j=1, #(socket_.plans) do
			local plans_ = socket_.plans[j]
			if(date_ >= plans_.time) then
				gpio.write(socket_.pin, 1-plans_.case)	-- 高电平断开
				data.socket[i].status = plans_.case
				if(plans_.isdaily == 1) then
					data.socket[i].plans[j].time = plans_.time + 86400
				else
					del[#del+1] = j
				end
			end
		end
		for k=#del, 1, -1 do
			table.remove(data.socket[i].plans, del[k])
		end
	end
	collectgarbage()
end



--[[ http服务器 ]]
-- url解码
function urlDecode(url)
	return url:gsub('%%(%x%x)', function(x)
		return string.char(tonumber(x, 16))
	end)
end

-- 解析请求行
function parseRequest(payload)
	payload = urlDecode(payload)
	local req = {}
	local _GET = {}
	local _, _, method, path, query = string.find(payload, "([A-Z]+) (.+)?(.+) HTTP")

	if(method == nil) then
		_, _, method, path = string.find(payload, "([A-Z]+) (.+) HTTP")
	end
	if(query ~= nil) then
        for k, v in string.gmatch(query, "([^&#]+)=([^&#]*)&*") do
			_GET[k] = v
		end
	end

	req.method = method
	req.query = _GET
	req.path = path

	return req
end

-- 文件类型
function getContentType(filename)
	local contentTypes = {
		[".css"] = "text/css",
		[".js"] = "application/javascript",
		[".html"] = "text/html",
		[".png"] = "image/png",
		[".jpg"] = "image/jpeg"
	}
	for ext, type_ in pairs(contentTypes) do
		if(string.sub(filename, -string.len(ext)) == ext) then
			return type_
		end
	end
	return "text/plain"
end

-- 关闭连接
function srvClose(conn)
	conn:on('sent', function() end)
	conn:on('receive', function() end)
	conn:close()
	conn = nil
	collectgarbage()
end

-- 发送文本
function srvSend(conn, body, o)
	local status, type_, length
	o = o or {}

	status = o.status or "200 OK"
	type_ = o.type or "text/html"
	length = string.len(body)

	local buf = "HTTP/1.1 " .. status .. "\r\n" ..
		"Content-Type: " .. type_ .. "\r\n" ..
		"Content-Length: " .. length .. "\r\n" ..
		"\r\n" ..
		body

	local function dosend()
		if buf == "" then
			srvClose(conn)
		else
			conn:send(string.sub(buf, 1, 1024))
			buf = string.sub(buf, 1025)
		end
	end

	dosend()
	conn:on("sent", dosend)
end

-- 发送文件
function srvSendFile(conn, filename, o)
	local status, type_, length
	o = o or {}

	if not file.exists(filename) then
		status = "404 Not Found"
		srvSend(conn, status, { status=status })
		return
	end

	status = o.status or "200 OK"
	type_ = o.type or getContentType(filename)

	file.open(filename,"r")
	length = file.seek("end")
	file.close()

	local header = "HTTP/1.1 " .. status .. "\r\n" ..
		"Content-Type: " .. type_ .. "\r\n" ..
		"Content-Length: " .. length .. "\r\n" ..
		"\r\n"

	local pos = 0;
	local function dosend()
		file.open(filename, "r")
		if(file.seek("set", pos) == nil) then
			srvClose(conn)
		else
			local buf2 = file.read(1024)
			conn:send(buf2)
			pos = pos + 1024
		end
		file.close()
	end

	conn:send(header)
	conn:on("sent", dosend)
end

-- 传入url的路径，发送对应的文件
function parsePath(conn, path)
	local filename = ""
	if path == "/" then
		filename = "index.html"
	else
		filename = string.gsub(string.sub(path, 2), "/", "_")
	end
	srvSendFile(conn, filename)
end



--[[ 主程序 ]]
-- 点亮指示灯
gpio.write(LED_SIGN, gpio.LOW)

-- 加载数据文件
setData(loadData(datafile))

-- 恢复开关状态
for i=1, data.socketcount do
	local socket_ = data.socket[i]
	gpio.mode(socket_.pin, gpio.OUTPUT)
	gpio.write(socket_.pin, 1-socket_.status)
end

-- 连接STA
if(data.wifimode == wifi.STATIONAP) then
	setStaap()
else
	setSta()
end
wifi.sta.autoconnect(1)

-- 服务器
srv = net.createServer(net.TCP)
srv:listen(80, function(conn)
    conn:on("receive", function(conn, payload)
		local req = parseRequest(payload)
		data.date = date_

		if(req.path == "/config") then
			local q = req.query or {}
			local i, n, s, p = (q.i and q.i-0), q.n, (q.s and q.s-0), q.p
			if(i) then
				if(n) then data.socket[i].name = n end
				if(s) then
					gpio.write(data.socket[i].pin, 1-s)
					data.socket[i].status = s
				end
				if(p) then
					local j = 1
					data.socket[i].plans = {}
					for d, c, t in string.gmatch(p, "(%d)(%d)(%d+)") do
						if not(d and c and t) then break end
						data.socket[i].plans[j] = {}
						data.socket[i].plans[j].isdaily = d-0
						data.socket[i].plans[j].case = c-0
						data.socket[i].plans[j].time = t-0
						j = j+1
					end
				end
			end
			saveData(datafile)
			srvSend(conn, cjson.encode(data), {type="application/json"})

		elseif(req.path == "/network") then
			local q = req.query.q
			if(q == "1") then
				local ssid = req.query.s
				if(ssid) then
					local psw = req.query.p
					psw = psw and #psw >= 8 and psw or "12345678"
					data.ssid = ssid
					data.password = psw
					wifi.sta.config(ssid, psw)
					wifistatus, wifistatus_ = 1, 1
					saveData(datafile)
					tmr.alarm(TMR_SERVER, 1000, 1, function()
						if(wifistatus ~= wifistatus_) then
							srvSend(conn, '['..wifistatus..',"'..(ip or '')..'"]')
							tmr.unregister(TMR_SERVER)
						end
					end)
				end
			elseif(q == "0") then
				wifi.sta.getap(function(table)
					srvSend(conn, cjson.encode(table), {type="application/json"})
				end)
			else
				srvSend(conn, '['..wifistatus..',"'..(ip or '')..'"]')
			end

		elseif(req.path == "/time") then
			local t = req.query.t
			if(t) then
				date_, data.date = t, t
			end
			srvSend(conn, ""..date_)

		else
			parsePath(conn, req.path)
		end

		collectgarbage()
    end)
end)

-- 主循环
tmr.alarm(TMR_MAINLOOP, 1000, tmr.ALARM_AUTO, function()
	date_ = date_+1
	if(date_%3600 == 0) then dateSyn() end

	wifistatus_ = wifistatus
	wifistatus = wifi.sta.status()

	checkPlans()
end)
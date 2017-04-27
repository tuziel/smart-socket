--[[ gpio/timer初始化 ]]
LED_SIGN = 4		-- 指示灯
TMR_MAINLOOP = 1	-- 主循环定时器
TMR_SIGN = 5		-- 指示灯定时器
TMR_SERVER = 6		-- Server定时器

gpio.mode(LED_SIGN, gpio.OUTPUT)


--[[ 变量初始化 ]]
datafile = 'data.json'			-- 数据保存文件
data = {}						-- 系统数据
date_ = 0						-- 系统时间
ip = nil						-- STA模式ip
stastatus = 0					-- wifi.sta.status()
remote = "ws://test.com"		-- 远程服务器地址
heartbeat = 0					-- 心跳为0时断开websocket连接
heartbeatmax = 20				-- 心跳初始为20秒


--[[ 数据初始化 ]]
function initData(data_)
	if(type(data_) ~= "table") then
		data_ = {}
	end

	-- 设备id, 然而并没有用到
	data.id = 0
	-- 系统时间
	data.date = (data_.date or 0)-0
	-- wifi名称
	data.ssid = data_.ssid ~= "" and data_.ssid or "ssid"
	-- wifi密码
	data.password = data_.password or "password"
	-- 插口数量
	data.socketcount = (data_.socketcount or 1)-0
	-- 插口数据
	data.socket = {}

	for i=1, data.socketcount do
		local socket_ = data_.socket and data_.socket[i] or {}
		local plans_ = socket_ and socket_.plans or {}

		data.socket[i] = {
			-- 插口标签
			name = socket_.name ~= "" and socket_.name or "socket"..i,
			-- 插口引脚
			pin = 4+i,
			-- 插口状态
			status = (socket_ and socket_.status or 1)-0,
			-- 任务计划
			plans = {}
		}
		if(plans_[1]) then
			for j=1, #plans_ do
				data.socket[i].plans[j] = {
					-- 触发时间
					time = (plans_[j].time or 0)-0,
					-- 触发操作
					case = (plans_[j].case or 1)-0,
					-- 是否每日循环
					isdaily = (plans_[j].isdaily or 0)-0
				}
			end
		end
	end

	date_ = data.date
	saveData(datafile)
end

-- 读取数据文件
function loadData(filename)
	local data_ = {}

	if file.open(filename) then
		data_ = file.read()
		file.close()
		print("loading " .. filename .. " Complete")
		return cjson.decode(data_)
	end

	print(filename .. " does not exist")
	return nil
end

-- 保存数据文件
function saveData(filename)
	local data_ = cjson.encode(data)

	file.open(filename, 'w')
	file.write(data_)
	file.close()
	print('saved ' .. filename .. ' Complete')
end


--[[ 设置wifi ]]
-- 设置STAAP模式
function setStaap()
	wifi.setmode(wifi.STATIONAP)
	wifi.sta.config(data.ssid, data.password)
	wifi.ap.config( {ssid = 'nodemcu', auth = wifi.OPEN} )
	wifi.ap.setip( {ip = "192.168.1.1", netmask = "255.255.255.0", gateway = "192.168.1.1"} )
end


--[[ 处理任务计划 ]]
function checkPlans()
	local flag = nil	-- 计划触发标识
	
	-- 循环处理排插计划
	for i=1, data.socketcount do
		local socket_ = data.socket[i]
		local del = {}
		
		for j=1, #(socket_.plans) do
			local plans_ = socket_.plans[j]
			
			-- 如果到达计划触发时间
			if(date_ >= plans_.time) then
				gpio.write(socket_.pin, plans_.case)	-- 低电平断开
				-- gpio.write(socket_.pin, 1-plans_.case)	-- 高电平断开
				data.socket[i].status = plans_.case
				-- 如果是每日计划，时间向后加一天(86400s)
				-- 如果不是，把计划放入删除列表
				if(plans_.isdaily == 1) then
					while(date_ >= plans_.time) do
						plans_.time = plans_.time + 86400
					end
					data.socket[i].plans[j].time = plans_.time
				else
					del[#del+1] = j
				end
			end
		end
		-- 如果删除列表有元素，倒序将删除列表中的计划删除
		if(#del > 0) then
			for k=#del, 1, -1 do
				table.remove(data.socket[i].plans, del[k])
			end
			flag = 1
		end
	end
	if(flag) then
		saveData(datafile)
		-- 完全不能理解为什么下面这句pushData()没有把信息发出去
		-- 明明可以打印出信息，然而服务器就是收不到。绝望的眼神.jpg
		pushData()
	end
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

-- http服务器业务
function httpSrv(conn)
    conn:on("receive", function(conn, payload)
		local req = parseRequest(payload)
		data.date = date_

		if(req.path == "/config") then
			local q = req.query or {}
			local i, n, s, p = (q.i and q.i-0), q.n, q.s, q.p
			if(i) then
				if(n) then data.socket[i].name = n end
				if(s) then
					gpio.write(data.socket[i].pin, s)		-- 低电平断开
					-- gpio.write(data.socket[i].pin, 1-s)		-- 高电平断开
					data.socket[i].status = s-0
				end
				if(p) then
					local j = 1
					data.socket[i].plans = {}
					for d, c, t in string.gmatch(p, "(%d)(%d)(%d+)") do
						if not(d and c and t) then break end
						data.socket[i].plans[j] = {
							isdaily = d-0,
							case = c-0,
							time = t-0,
						}
						j = j+1
					end
				end
				saveData(datafile)
			end
			srvSend(conn, cjson.encode(data), {type="application/json"})
			pushData()

		elseif(req.path == "/network") then
			local q = req.query.q
			if(q == "1" or q == "2") then
				local ssid = req.query.s
				if(ssid) then
					if(q == "1") then
						tmr.alarm(TMR_SERVER, 1000, 1, function()
							if(stastatus ~= 1) then
								srvSend(conn, '['..stastatus..',"'..(ip or '')..'"]')
								tmr.unregister(TMR_SERVER)
							end
						end)
					else
						srvClose(conn);
					end
					local psw = req.query.p
					psw = psw and #psw >= 8 and psw or "12345678"
					data.ssid = ssid
					data.password = psw
					wifi.sta.config(ssid, psw)
					saveData(datafile)
				else
					srvSend(conn, '['..stastatus..',"'..(ip or '')..'"]')
				end
			elseif(q == "0") then
				wifi.sta.getap(function(table)
					srvSend(conn, cjson.encode(table), {type="application/json"})
				end)
			else
				srvSend(conn, '['..stastatus..',"'..(ip or '')..'"]')
			end

		elseif(req.path == "/time") then
			local t = req.query.t
			if(t and heartbeat == 0) then
				date_, data.date = t, t
			end
			saveData(datafile)
			srvSend(conn, ""..date_)

		else
			parsePath(conn, req.path)
		end

		collectgarbage()
    end)
end


--[[ 远程服务 ]]
function onConnect(ws)
	heartbeat = heartbeatmax
	print('got ws connection')
	pushData()
	ws:send('{"type":"time"}')
end
function onReceive(_, msg, opcode)
	heartbeat = heartbeatmax
	print("got message ", msg)
	local data_ = cjson.decode(msg)
	if(data_.type == "time") then
		data.date, date_ = data_.time, data_.time
		saveData(datafile)
	elseif(data_.type == "set") then
		local i, n, s, p = data_.id+1, data_.name, data_.status, data_.plans
		if(i) then
			if(n) then data.socket[data_.id+1].name = n end
			if(s) then
				gpio.write(data.socket[i].pin, s)		-- 低电平断开
				-- gpio.write(data.socket[i].pin, 1-s)		-- 高电平断开
				data.socket[i].status = s-0
			end
			if(p) then data.socket[data_.id+1].plans = p end
			saveData(datafile)
			pushData()
		end
	end
end
function onClose(_, status)
	heartbeat = 0
	print('connection closed', status)
end
function pushData()
	if(heartbeat > 0) then
		local data_ = '{"type":"mcu", "key":"'..__KEY__..'", "data":'..cjson.encode(data)..'}'
		ws:send(data_)
		print("push ", data_)
	end
end


--[[ 主程序 ]]
-- 点亮指示灯
gpio.write(LED_SIGN, gpio.LOW)

-- 加载数据文件
initData(loadData(datafile))

-- 恢复开关状态
for i=1, data.socketcount do
	local socket_ = data.socket[i]
	gpio.mode(socket_.pin, gpio.OUTPUT)
	gpio.write(socket_.pin, socket_.status)		-- 低电平断开
	-- gpio.write(socket_.pin, 1-socket_.status)	-- 高电平断开
end

-- wifi设置
setStaap()
wifi.sta.autoconnect(1)

-- 开启服务器
srv = net.createServer(net.TCP)
srv:listen(80, httpSrv)

-- 开启远程服务
ws = websocket.createClient()
ws:on("connection", onConnect)
ws:on("receive", onReceive)
ws:on("close", onClose)

-- 主循环
tmr.alarm(TMR_MAINLOOP, 1000, 1, function()
	-- 时钟
	date_ = date_+1

	-- 每小时向服务器请求一次时间
	if(date_%3600 == 0 and stastatus == 5 and heartbeat > 0) then
		ws:send('{"type":"time"}')
	end

	-- 心跳
	if(heartbeat > 0) then
		heartbeat = heartbeat-1
	else
		gpio.write(LED_SIGN, 1)
		tmr.alarm(TMR_SIGN, 500, 0, function()
			gpio.write(LED_SIGN, 0)
		end)
	end
	if(date_%10 == 0 and stastatus == 5) then
		if(heartbeat > 0) then
			ws:send('{"type":"ping"}')
		else
			ws:connect(remote)
		end
	end

	-- wifi状态(不用事件注册eventMonReg是因为内存不够，不用RCT等等同理)
	if(stastatus ~= wifi.sta.status()) then
		stastatus = wifi.sta.status()

		if(stastatus == 0) then
			print("STA_IDLE")
		elseif(stastatus == 1) then
			print("STA_CONNECTING")
		elseif(stastatus == 2) then
			print("STA_WRONGPWD")
		elseif(stastatus == 3) then
			print("STA_APNOTFOUND")
		elseif(stastatus == 4) then
			print("STA_FAIL")
		elseif(stastatus == 5) then
			ip = wifi.sta.getip()
			print("STA_GOTIP " .. ip)
			ws:connect(remote)
		end
	end

	checkPlans()
end)
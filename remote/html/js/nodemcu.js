// 变量
var data = {};						// 存放数据
var remoteURL = "ws://test.com/";	// 服务器url

// UI
function Socket(i) {
	var elm = $(document.createElement("div")),
		k = data.socket[i],
		n = k.name || "开关" + (i + 1),
		s = k.status ? 1 : 0;
	elm.addClass("socket");
	elm.html(
		'<p class="summary">' +
		'<a class="i-arrow"></a>' +
		'<span>' + n + '</span>' +
		'<a class="switch' + (s ? " act" : "") + '"><input type="button"></a>' +
		'</p>' +
		'<ul class="detail">' +
		'<li>' +
		'<span>标签</span>' +
		'<input type="text" class="s_n" value="' + n + '" maxlength="10">' +
		'</li>' +
		'<h3 class="rela"><span>计划</span><a class="i-add"></a></h3>' +
		'<li>' +
		'<ul class="plans-list"></ul>' +
		'</li>' +
		'<li class="t-c">' +
		'<input type="button" class="submit" value="保存">' +
		'</li>' +
		'</ul>'
	);
	elm.find(".summary").on("click", function () {
		var detail = $(this).next();
		var swc = $(this).find(".i-arrow");
		if (detail.css("display") == "block") {
			detail.hide();
			swc.removeClass("act");
		} else {
			$(".detail").hide();
			$(".i-arrow").removeClass("act");
			detail.show();
			swc.addClass("act");
		}
	});
	elm.find(".switch").on("click", function (e) {
		s = data.socket[i].status = 1 - s;
		$(this)[s ? "addClass" : "removeClass"]("act");
		sendData({
			"id": i,
			"status": s
		});
		e.stopPropagation();
	});
	elm.find(".i-add").on("click", function () {
		var l = data.socket[i].plans.length,
			cur = $(this).parents(".detail").find(".plans-list");
		data.socket[i].plans[l] = {
			time: Math.floor(new Date().setSeconds(0) / 1000) + 6e2,
			isdaily: 0,
			case: 0
		}
		cur.append(Plans(i, l));
	});
	elm.find(".s_n").on("change", function () {
		n = data.socket[i].name = $(this).val();
	});
	elm.find(".submit").on("click", function () {
		sendData({
			"id": i,
			"name": n,
			"plans": data.socket[i].plans
		});
	});
	return elm;
}
function formatTime(t) {
	t = (t - 0 < 10 ? "0" : "") + t;
	return t;
}
function limitNum(v, l) {
	v = v.match(/^[0-9]{0,2}/)[0];
	while (v - 0 > l) {
		v = v.replace(/.$/, "");
	}
	return v;
}
function Plans(i, j) {
	var item = $(document.createElement("li")),
		p = data.socket[i].plans[j],
		d = p.isdaily ? 1 : 0,
		c = p.case ? 1 : 0,
		t = new Date(p.time * 1000),
		h = t.getHours(),
		m = t.getMinutes();
	item.addClass("plans");
	item.html(
		'<a class="i-remove"></a>' +
		'<input type="button" class="s_d" value="' + (d ? "每天" : "一次") + '">' +
		'<input type="text" class="s_h" value="' + formatTime(h) + '">:' +
		'<input type="text" class="s_m" value="' + formatTime(m) + '">' +
		'<input type="button" class="s_c" value="' + (c ? "开" : "关") + '">'
	);
	item.find(".i-remove").on("click", function () {
		var cur = $(this).parents(".plans");
		cur.remove();
		delete (data.socket[i].plans[j]);
	});
	item.find(".s_d").on("click", function () {
		d = 1 - d;
		$(this).val(d == 1 ? "每天" : "一次");
		data.socket[i].plans[j].isdaily = d;
	});
	item.find(".s_h").on("input", function () {
		$(this).val(limitNum($(this).val(), 23));
	});
	item.find(".s_h").on("change", function () {
		var t_ = new Date();
		v = $(this).val();
		$(this).val(formatTime(v));
		t.setHours(v);
		while (t > t_) {
			t -= 864e5;
		}
		while (t < t_) {
			t = +t + 864e5;
		}
		t = new Date(t);
		data.socket[i].plans[j].time = t / 1e3;
	});
	item.find(".s_m").on("input", function () {
		$(this).val(limitNum($(this).val(), 60));
	});
	item.find(".s_m").on("change", function () {
		var t_ = new Date();
		v = $(this).val();
		$(this).val(formatTime(v));
		t.setMinutes(v);
		while (t > t_) {
			t -= 864e5;
		}
		while (t < t_) {
			t = +t + 864e5;
		}
		t = new Date(t);
		data.socket[i].plans[j].time = t / 1e3;
	});
	item.find(".s_c").on("click", function () {
		c = 1 - c;
		$(this).val(c == 1 ? "开" : "关");
		data.socket[i].plans[j].case = c;
	});
	return item;
}

function setPage() {
	var i, j, l;
	$(".socket").remove();
	$(".plans").remove();
	for (i = 0; i < data.socketcount; i++) {
		$("#config").append(Socket(i));
		if (!data.socket[i].plans[0]) {
			data.socket[i].plans = [];
		}
		l = data.socket[i].plans.length;
		for (j = 0; j < l; j++) {
			$(".plans-list").eq(i).append(Plans(i, j));
		}
	}
}
function setInfo(info) {
	var i = 0;
	var timer = setInterval(function() {
		$("#info").css("color", "rgba(48,48,48,"+(++i/10)+")");
		if(i>=10) {
			clearInterval(timer);
		}
	}, 30);
	$("#info").text(info).css("color", "rgba(48,48,48,0)");
}

// websocket
var socket = new WebSocket(remoteURL);
socket.onopen = handleOpen;
socket.onclose = handleClose;
socket.onmessage = handleMsg;
socket.onerror = handleError;

function handleOpen() {
	setInfo("正在连接SmartHome设备");
}
function handleClose() {
	setInfo("无法连接到SmartHome服务器");
	socket.close();
};
function handleMsg(evt) {
	console.log("evt.data", evt.data);
	var data_ = {};
	try {
		data_ = JSON.parse(evt.data);
	} catch (err) {
		data_.type = "msg";
		data_.msg = evt.data;
	}

	if(data_.type == "push") {
		data = data_.data;
		setPage();
		setInfo("已连接到SmartHome设备");
	} else if(data_.type == "msg") {
		setInfo(data_.msg);
	}
	console.log("data_", data_);

};
function handleError(evt) {
	setInfo(evt.data || "未知错误");
}
function sendData(obj) {
	var data_ = {"type":"set"};
	obj = obj || {};
	(obj.id !== undefined) && (data_.id = obj.id);
	(obj.name !== undefined) && (data_.name = obj.name);
	(obj.status !== undefined) && (data_.status = obj.status);
	(obj.plans !== undefined) && (data_.plans = obj.plans);

	if(socket.readyState == 1) {
		socket.send(JSON.stringify(data_));
	} else {
		setInfo("无法连接到SmartHome服务器");
	}
	console.log("json", JSON.stringify(data_));
}

setInterval(function() {
	if(socket.readyState == 1) {
		socket.send('{"type":"ping"}');
	} else {
		setInfo("无法连接到SmartHome服务器");
	}
}, 10000);
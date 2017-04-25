<?php
require_once __DIR__ . '/Workerman/Autoloader.php';
use Workerman\Worker;
use Workerman\Lib\Timer;

Worker::$stdoutFile = __DIR__ . '/Workerman/Autoloader.php';

// 心跳间隔30秒
define('HEARTBEAT_TIME', 30);

$global_uid = 0;
// 存放nodemcu的连接
$nodemcu_conn = null;
// 存放nodemcu的信息
$nodemcu_data = new stdclass();

function format_msg($msg) {
	$str = '{"type":"msg","msg":"'.$msg.'"}';
	return $str;
}
function format_data($data) {
	$str = '{"type":"push","data":'.json_encode($data).'}';
	return $str;
}

function handle_start($worker) {
	// 心跳
	Timer::add(1, function()use($worker){
		$time_now = time();
		foreach($worker->connections as $connection) {
			// 有可能该connection还没收到过消息，则lastMessageTime设置为当前时间
			if (empty($connection->lastMessageTime)) {
				$connection->lastMessageTime = $time_now;
				continue;
			}
			// 上次通讯时间间隔大于心跳间隔，则认为客户端已经下线，关闭连接
			if ($time_now - $connection->lastMessageTime > HEARTBEAT_TIME) {
				$connection->close();
			}
		}
	});
};

// 当客户端连上来时分配uid，并保存连接，并通知所有客户端
function handle_connection($connection) {
	global $worker, $global_uid, $nodemcu_conn, $nodemcu_data;
	// 为这个链接分配一个uid
	$connection->uid = ++$global_uid;

	if($nodemcu_conn) {
		$connection->send(format_data($nodemcu_data));
	} else {
		$connection->send(format_msg("无法连接到SmartHome设备"));
	}
}

// 当客户端发送消息过来时，转发给所有人
function handle_message($connection, $data) {
	global $worker, $nodemcu_conn, $nodemcu_data;

	$connection->lastMessageTime = time();

	if( !($data_ = json_decode($data)) ) {
		$data_ = new stdclass();
		$data_->type = 'msg';
		$data_->msg = $data;
	}
	var_dump($data_);
	if($data_->type === 'mcu') {
		$nodemcu_conn = $connection;
		$nodemcu_data = $data_->data;
		foreach($worker->connections as $conn) {
			if($conn !== $nodemcu_conn) {
				$conn->send(format_data($nodemcu_data));
			} else {
				$connection->send('{"type":"time","time":'.date_timestamp_get(date_create()).'}');
			}
		}
	}
	if($nodemcu_conn) {
		if($data_->type === 'set') {
			if(!isset($data_->id) || $data_->id >= $nodemcu_data->socketcount) {
				$connection->send(format_msg("错误的插口号"));
				return;
			}
			if(isset($data_->name)) {
				($nodemcu_data->socket[$data_->id]->name = $data_->name) ||
				($nodemcu_data->socket[$data_->id]->name = "开关".$data_->id);
			}
			if(isset($data_->status)) {
				($nodemcu_data->socket[$data_->id]->status = $data_->status) ||
				($nodemcu_data->socket[$data_->id]->status = 0);
			}
			if(isset($data_->plans)) {
				$plans = $data_->plans;
				$plans_ = array();
				for($i=0, $j=0; $i<sizeof($plans); $i++) {
					if(isset($plans[$i]->time) && isset($plans[$i]->case) && isset($plans[$i]->isdaily)) {
						$plans_[$j++] = $plans[$i];
					}
				}
				$nodemcu_data->socket[$data_->id]->plans = $plans_;
				$data_->plans = $plans_;
			}
			foreach($worker->connections as $conn) {
				if($conn !== $nodemcu_conn) {
					$conn->send(format_data($nodemcu_data));
				} else {
					$conn->send(json_encode($data_));
				}
			}
		} elseif($data_->type === 'time')  {
			$connection->send('{"type":"time","time":'.date_timestamp_get(date_create()).'}');
		}
		else {
			$connection->send('{"type":"ping"}');
		}
	} else {
		$connection->send(format_msg("无法连接到SmartHome设备"));
	}
}

// 当客户端断开时，广播给所有客户端
function handle_close($connection) {
	global $worker, $nodemcu_conn;

	if ($connection === $nodemcu_conn) {
		$nodemcu_conn = null;
		foreach($worker->connections as $conn) {
			$conn->send(format_msg("与SmartHome设备的连接已断开"));
		}
	}
}

// 创建一个文本协议的Worker监听80接口
$worker = new Worker('websocket://0.0.0.0:80');

// 只启动1个进程，这样方便客户端之间传输数据
$worker->count = 1;

$worker->onWorkerStart = 'handle_start';
$worker->onConnect = 'handle_connection';
$worker->onMessage = 'handle_message';
$worker->onClose = 'handle_close';


Worker::runAll();
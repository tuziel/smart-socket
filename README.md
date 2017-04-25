# 智能排插

一个基于nodemcu的智能排插

## 固件说明

通过云构建生成，包含9个模块：`cjson`, `file`, `gpio`, `net`, `node`, `tmr`, `uart`, `websocket`, `wifi`。
也可以直接使用这里的 `nodemcu-master-9-modules-2017-04-24-20-59-43-integer.bin`。

之后用ESPlore把 `init.lua`, `index.html`, `data.json` 3个文件烧进nodemcu里就可以开始用了。

## 服务器文件说明

服务器文件放在`remote`文件夹里，使用了[workerman框架](http://www.workerman.net/)。

`html`文件夹是入口文件
`workerman`文件夹包含workerman框架和主程序`nodemcu.php`

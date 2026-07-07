#!/bin/bash

#查看所有注册类型为embedding的模型
xinference registrations --model-type embedding --endpoint http://localhost:9997

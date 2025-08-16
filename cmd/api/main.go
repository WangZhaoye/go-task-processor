package main

import (
	"github.com/WangZhaoye/go-task-processor/internal/config"
	"github.com/WangZhaoye/go-task-processor/internal/db"
	"github.com/WangZhaoye/go-task-processor/internal/handler"
	"github.com/WangZhaoye/go-task-processor/internal/mq"
	"github.com/gin-gonic/gin"
)

func main() {
	config.LoadConfig()
	db.InitDB()
	mq.InitRabbitMQ()
	r := gin.Default()
	handler.RegisterRoutes(r)
	r.Run(":" + config.Cfg.Port)
}

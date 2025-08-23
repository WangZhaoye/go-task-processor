// @title Go Task Processor API
// @version 1.0
// @description This is a task async processing API.
// @host localhost:8080
// @BasePath /

// @schemes http
package main

import (
	_ "github.com/WangZhaoye/go-task-processor/docs"
	"github.com/WangZhaoye/go-task-processor/internal/cache"
	"github.com/WangZhaoye/go-task-processor/internal/config"
	"github.com/WangZhaoye/go-task-processor/internal/db"
	"github.com/WangZhaoye/go-task-processor/internal/handler"
	"github.com/WangZhaoye/go-task-processor/internal/mq"
	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

func main() {
	config.LoadConfig()
	db.InitDB()
	mq.InitRabbitMQ()
	cache.InitRedis()
	r := gin.Default()
	handler.RegisterRoutes(r)

	// ✅ Swagger 文档路由
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	r.Run(":" + config.Cfg.Port)
}

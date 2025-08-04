package handler

import (
	"github.com/WangZhaoye/go-task-processor/internal/service"
	"github.com/gin-gonic/gin"
)

func RegisterRoutes(r *gin.Engine) {
	r.POST("/tasks", service.CreateTask)
	r.GET("/tasks/:id", service.GetTask)
}

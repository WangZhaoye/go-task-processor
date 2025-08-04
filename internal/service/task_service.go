package service

import (
	"fmt"

	"github.com/gin-gonic/gin"
)

type TaskRequest struct {
	Type    string `json:"type" binding:"required"`
	Payload string `json:"payload" binding:"required"`
}

func CreateTask(c *gin.Context) {
	fmt.Println("create task")
	c.JSON(200, gin.H{"status": "ok"}) 
}

func GetTask(c *gin.Context) {
	fmt.Println("get task")
}

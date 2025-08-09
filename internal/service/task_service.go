package service

import (
	"fmt"
	"net/http"
	"time"

	"github.com/WangZhaoye/go-task-processor/internal/db"
	"github.com/WangZhaoye/go-task-processor/internal/model"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type TaskRequest struct {
	Type    string `json:"type" binding:"required"`
	Payload string `json:"payload" binding:"required"`
}

func CreateTask(c *gin.Context) {
	var req TaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	task := model.Task{
		ID: uuid.New(),
		Type: req.Type,
		Payload: req.Payload,
		Status: model.StatusPending,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	//create in DB
	if err := db.DB.Create(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save task"})
		return
	}

	//push to MQ

	fmt.Println("create task in DB ✅")
	c.JSON(http.StatusCreated, task) 
}

func GetTask(c *gin.Context) {
	id := c.Param("id")
	uuidVal, err := uuid.Parse(id)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error":  "Task not found"})
		return
	}
	var task model.Task
	if err := db.DB.First(&task, "id = ?", uuidVal).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}
	fmt.Println("get task ✅")
	c.JSON(http.StatusOK, task)
}

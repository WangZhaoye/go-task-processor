package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/WangZhaoye/go-task-processor/internal/db"
	"github.com/WangZhaoye/go-task-processor/internal/model"
	"github.com/WangZhaoye/go-task-processor/internal/mq"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type TaskRequest struct {
	Id      string `json:"id" binding:"omitempty,uuid4"`
	Type    string `json:"type" binding:"required"`
	Payload string `json:"payload" binding:"required"`
}

func CreateTask(c *gin.Context) {
	var req TaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var id uuid.UUID
	if req.Id == "" {
		id = uuid.New()
	} else {
		var err error
		id, err = uuid.Parse(req.Id)
		if err != nil {
			c.JSON(400, gin.H{"error": "Invalid UUID format for id"})
			return
		}
	}
	task := model.Task{
		ID:        id,
		Type:      req.Type,
		Payload:   req.Payload,
		Status:    model.StatusPending,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	//create in DB
	if err := db.DB.Create(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save task"})
		return
	}
	fmt.Println("✅ create task in DB ")

	//push to MQ
	taskJson, _ := json.Marshal(task)
	if err := mq.PublishTask(string(taskJson)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to enqueue task"})
		return
	}
	fmt.Println("✅ create task in MQ")

	c.JSON(http.StatusCreated, task)
}

func GetTask(c *gin.Context) {
	id := c.Param("id")
	uuidVal, err := uuid.Parse(id)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Task not found"})
		return
	}
	var task model.Task
	if err := db.DB.First(&task, "id = ?", uuidVal).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}
	fmt.Println("✅ get task from DB")
	c.JSON(http.StatusOK, task)
}

func UpdateTaskStatus(id uuid.UUID, status model.TaskStatus) error {
	return db.DB. // 1. 从全局 DB 变量开始操作（GORM 的 *gorm.DB 实例）

			Model(&model.Task{}). // 2. 指定要操作的表（根据 Task 模型）

			Where("id = ?", id). // 3. 添加 SQL 条件：WHERE id = '具体的UUID值'

			Updates(map[string]interface{}{ // 4. 更新多列
			"status":     status,     // 更新 status 列
			"updated_at": time.Now(), // 更新 updated_at 列为当前时间
		}).
		Error // 5. 返回执行过程中的错误（nil 表示成功）
}

func FinishTask(id uuid.UUID, result string, status model.TaskStatus) error {
	return db.DB.
		Model(&model.Task{}).
		Where("id = ?", id).
		Updates(map[string]interface{}{
			"status":     status,
			"result":     result,
			"updated_at": time.Now(),
		}).Error
}

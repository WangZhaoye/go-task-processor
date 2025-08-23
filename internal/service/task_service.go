package service

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/WangZhaoye/go-task-processor/internal/cache"
	"github.com/WangZhaoye/go-task-processor/internal/db"
	"github.com/WangZhaoye/go-task-processor/internal/model"
	"github.com/WangZhaoye/go-task-processor/internal/mq"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type TaskRequest struct {
	Type    string `json:"type" binding:"required"`
	Payload string `json:"payload" binding:"required"`
}

// CreateTask godoc
// @Summary Create a new task
// @Description Submit a task to be processed asynchronously
// @Tags tasks
// @Accept json
// @Produce json
// @Param task body model.Task true "Task"
// @Success 200 {object} map[string]string
// @Failure 400 {object} map[string]string
// @Router /tasks [post]
func CreateTask(c *gin.Context) {
	var req TaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 总是生成新的UUID
	id := uuid.New()
	
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

	// 缓存新创建的任务
	if err := cache.CacheTask(task.ID.String(), task); err != nil {
		fmt.Printf("⚠️ Failed to cache task: %v\n", err)
		// 缓存失败不影响主流程
	}

	// 缓存任务状态
	if err := cache.CacheTaskStatus(task.ID.String(), string(task.Status)); err != nil {
		fmt.Printf("⚠️ Failed to cache task status: %v\n", err)
	}

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

	// 先尝试从缓存获取
	found, err := cache.GetCachedTask(id, &task)
	if err != nil {
		fmt.Printf("⚠️ Cache error: %v\n", err)
		// 缓存错误，继续从数据库查询
	} else if found {
		fmt.Println("✅ get task from cache")
		c.JSON(http.StatusOK, task)
		return
	}

	// 缓存未命中，从数据库查询
	if err := db.DB.First(&task, "id = ?", uuidVal).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}
	fmt.Println("✅ get task from DB")

	// 将查询结果缓存起来
	if err := cache.CacheTask(id, task); err != nil {
		fmt.Printf("⚠️ Failed to cache task after DB query: %v\n", err)
	}

	c.JSON(http.StatusOK, task)
}

// TaskUpdateOptions 定义任务更新选项
type TaskUpdateOptions struct {
	Status     *model.TaskStatus `json:"status,omitempty"`
	Result     *string           `json:"result,omitempty"`
	RetryCount *int              `json:"retry_count,omitempty"`
}

// UpdateTask 通用的任务更新方法，支持选择性更新字段
func UpdateTask(id uuid.UUID, options TaskUpdateOptions) error {
	updateFields := map[string]interface{}{
		"updated_at": time.Now(),
	}

	// 根据选项添加需要更新的字段
	if options.Status != nil {
		updateFields["status"] = *options.Status
	}
	if options.Result != nil {
		updateFields["result"] = *options.Result
	}
	if options.RetryCount != nil {
		updateFields["retry_count"] = *options.RetryCount
	}

	// 执行数据库更新
	err := db.DB.
		Model(&model.Task{}).
		Where("id = ?", id).
		Updates(updateFields).
		Error

	if err != nil {
		return err
	}

	// 更新缓存中的任务状态（如果状态有变化）
	if options.Status != nil {
		if statusErr := cache.CacheTaskStatus(id.String(), string(*options.Status)); statusErr != nil {
			fmt.Printf("⚠️ Failed to update cached task status: %v\n", statusErr)
		}
	}

	// 删除完整任务缓存，强制下次查询时重新从数据库获取最新数据
	if cacheErr := cache.InvalidateTaskCache(id.String()); cacheErr != nil {
		fmt.Printf("⚠️ Failed to invalidate task cache: %v\n", cacheErr)
	}

	return nil
}

// UpdateTaskStatus 更新任务状态（保持向后兼容）
func UpdateTaskStatus(id uuid.UUID, status model.TaskStatus) error {
	return UpdateTask(id, TaskUpdateOptions{
		Status: &status,
	})
}

// FinishTask 完成任务（保持向后兼容）
func FinishTask(id uuid.UUID, result string, status model.TaskStatus) error {
	return UpdateTask(id, TaskUpdateOptions{
		Status: &status,
		Result: &result,
	})
}

// UpdateTaskRetryCount 更新任务重试次数（保持向后兼容）
func UpdateTaskRetryCount(id uuid.UUID, retryCount int) error {
	return UpdateTask(id, TaskUpdateOptions{
		RetryCount: &retryCount,
	})
}

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"time"

	"github.com/WangZhaoye/go-task-processor/internal/cache"
	"github.com/WangZhaoye/go-task-processor/internal/config"
	"github.com/WangZhaoye/go-task-processor/internal/db"
	"github.com/WangZhaoye/go-task-processor/internal/model"
	"github.com/WangZhaoye/go-task-processor/internal/mq"
	"github.com/WangZhaoye/go-task-processor/internal/service"
)

const (
	MaxRetryCount = 3               // 最大重试次数
	RetryDelay    = 2 * time.Second // 重试延迟
)

func main() {
	config.LoadConfig()
	db.InitDB()
	mq.InitRabbitMQ()
	cache.InitRedis()

	msgs, err := mq.Channel.Consume(
		mq.Queue.Name, // 1. queue - 要消费的队列名
		"",            // 2. consumer - 消费者标签（留空让 RabbitMQ 自动生成）
		true,          // 3. autoAck - 是否自动确认消息（true 表示收到就算处理完成）
		false,         // 4. exclusive - 是否独占队列（true 表示只允许这个消费者连接）
		false,         // 5. noLocal - 不接收自己发送的消息（一般 RabbitMQ 不支持）
		false,         // 6. noWait - 是否不等待服务器响应（false 表示要等）
		nil,           // 7. args - 额外参数（一般 nil）
	)
	if err != nil {
		log.Fatalf("Failed to register RabbitMQ consumer: %v", err)
	}
	log.Println("🚀 Worker started. Waiting for tasks...")

	forever := make(chan bool)
	go func() {
		for d := range msgs {
			go handleTask(d.Body)
		}
	}()
	<-forever
}

func handleTask(body []byte) {
	var task model.Task
	if err := json.Unmarshal(body, &task); err != nil {
		log.Printf("❌ Invalid task format: %v\n", err)
		return
	}

	// 幂等校验
	// taskKey := fmt.Sprintf("task: %s", task.ID)
	// if !cache.SetIfNotExist(taskKey) {
	// 	log.Printf("⚠️ Task %s already being processed or done. Skipping... \n", task.ID)
	// 	return
	// }
	// log.Printf("📥 Received task: %s (%s), Retry Count: %d\n", task.ID, task.Type, task.RetryCount)

	// 更新状态为 running
	if err := service.UpdateTaskStatus(task.ID, model.StatusRunning); err != nil {
		log.Printf("❌ Failed to update task to running: %v\n", err)
		return
	}

	// 执行任务处理
	if err := processTask(&task); err != nil {
		log.Printf("❌ Task %s failed: %v\n", task.ID, err)
		handleTaskFailure(&task, err)
		return
	}

	// 任务成功完成
	result := fmt.Sprintf("Task %s completed successfully", task.ID)
	if err := service.FinishTask(task.ID, result, model.StatusSuccess); err != nil {
		log.Printf("❌ Failed to finish task %v \n", err)
		return
	}
	log.Printf("✅ Task %s done. \n", task.ID)
}

// processTask 模拟任务处理逻辑，可能会失败
func processTask(task *model.Task) error {
	// 模拟处理耗时任务
	time.Sleep(time.Second)

	// 模拟30%的失败率（用于演示重试功能）
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	if r.Float32() < 0.3 {
		return fmt.Errorf("simulated task processing error")
	}

	// 根据任务类型执行不同的处理逻辑
	switch task.Type {
	case "email":
		return processEmailTask(task)
	case "data_sync":
		return processDataSyncTask(task)
	default:
		return processDefaultTask(task)
	}
}

// handleTaskFailure 处理任务失败，决定是否重试
func handleTaskFailure(task *model.Task, taskErr error) {
	if task.RetryCount < MaxRetryCount {
		// 还可以重试
		task.RetryCount++
		log.Printf("🔄 Retrying task %s (attempt %d/%d) after %v\n",
			task.ID, task.RetryCount, MaxRetryCount, RetryDelay)

		// 更新重试计数
		if err := service.UpdateTaskRetryCount(task.ID, task.RetryCount); err != nil {
			log.Printf("❌ Failed to update retry count: %v\n", err)
			return
		}

		// 延迟后重新发布任务到队列
		go func() {
			time.Sleep(RetryDelay)
			retryTask(task)
		}()
	} else {
		// 达到最大重试次数，标记为失败
		log.Printf("💀 Task %s failed permanently after %d attempts\n", task.ID, MaxRetryCount)
		errorMsg := fmt.Sprintf("Task failed after %d retries. Last error: %v", MaxRetryCount, taskErr)
		if err := service.FinishTask(task.ID, errorMsg, model.StatusFalied); err != nil {
			log.Printf("❌ Failed to mark task as failed: %v\n", err)
		}
	}
}

// retryTask 重新发布任务到消息队列
func retryTask(task *model.Task) {
	taskJson, err := json.Marshal(task)
	if err != nil {
		log.Printf("❌ Failed to marshal retry task: %v\n", err)
		return
	}

	if err := mq.PublishTask(string(taskJson)); err != nil {
		log.Printf("❌ Failed to republish retry task: %v\n", err)
		return
	}
	log.Printf("🔄 Task %s republished for retry\n", task.ID)
}

// 不同类型任务的处理函数
func processEmailTask(task *model.Task) error {
	log.Printf("📧 Processing email task: %s\n", task.Payload)
	// 模拟邮件发送逻辑
	return nil
}

func processDataSyncTask(task *model.Task) error {
	log.Printf("🔄 Processing data sync task: %s\n", task.Payload)
	// 模拟数据同步逻辑
	return nil
}

func processDefaultTask(task *model.Task) error {
	log.Printf("⚙️ Processing default task: %s\n", task.Payload)
	// 模拟默认任务处理逻辑
	return nil
}

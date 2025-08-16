package main

import (
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/WangZhaoye/go-task-processor/internal/cache"
	"github.com/WangZhaoye/go-task-processor/internal/config"
	"github.com/WangZhaoye/go-task-processor/internal/db"
	"github.com/WangZhaoye/go-task-processor/internal/model"
	"github.com/WangZhaoye/go-task-processor/internal/mq"
	"github.com/WangZhaoye/go-task-processor/internal/service"
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
	taskKey := fmt.Sprintf("task: %s", task.ID)
	if !cache.SetIfNotExist(taskKey) {
		log.Printf("⚠️ Task %s already being processed or done. Skipping... \n", task.ID)
		return
	}
	log.Printf("📥 Received task: %s (%s)\n", task.ID, task.Type)
	// 更新状态为 running
	if err := service.UpdateTaskStatus(task.ID, model.StatusRunning); err != nil {
		log.Printf("❌ Failed to update task to running: %v\n", err)
		return
	}
	// 模拟处理耗时任务
	time.Sleep(time.Second)
	// 更新状态为 success + 设置结果
	result := fmt.Sprintf("Task %s completed successfully", task.ID)
	if err := service.FinishTask(task.ID, result, model.StatusSuccess); err != nil {
		log.Printf("❌ Failed to finish task %v \n", err)
		return
	}
	log.Printf("✅ Task %s done. \n", task.ID)
}

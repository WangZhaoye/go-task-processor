package mq

import (
	"log"

	"github.com/WangZhaoye/go-task-processor/internal/config"
	"github.com/streadway/amqp"
)

var Channel *amqp.Channel
var Queue amqp.Queue

func InitRabbitMQ() {
	conn, err := amqp.Dial(config.Cfg.RabbitMQUrl)
	if err != nil {
		log.Fatalf("Failed to connect to RabbitMQ: %v", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		log.Fatalf("Failed to open RabbitMQ channel: % v", err)
	}

	q, err := ch.QueueDeclare(
		"task_queue", // queue name
        true,         // durable
        false,        // delete when unused
        false,        // exclusive
        false,        // no-wait
        nil,          // arguments
	)
	if err != nil {
		log.Fatalf("Failled to declare RabbitMQ queue %v", err)
	}

	Channel = ch
	Queue = q
	log.Println("✅ Connected to RabbitMQ and declared queue.")
}

func PublishTask(body string) error {
	err := Channel.Publish(
		"",         // exchange
        Queue.Name, // routing key (queue name)
        false,      // mandatory
        false,      // immediate
		amqp.Publishing{
			DeliveryMode: amqp.Persistent, 
			ContentType: "application/json",
			Body: []byte(body),
		},
	)
	return err
}
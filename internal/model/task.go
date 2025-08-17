package model

import (
	"time"

	"github.com/google/uuid"
)

type TaskStatus string

const (
	StatusPending TaskStatus = "pending"
	StatusRunning TaskStatus = "running"
	StatusSuccess TaskStatus = "success"
	StatusFalied  TaskStatus = "failed"
)

type Task struct {
	ID         uuid.UUID  `gorm:"type:uuid;default:uuid_generate_v4();primaryKey" json:"id"`
	Type       string     `json:"Type"`
	Payload    string     `json:"payload"`
	Status     TaskStatus `json:"status"`
	Result     string     `json:"result"`
	RetryCount int        `json:"retry_count" gorm:"default:0"`
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

package db

import (
	"fmt"
	"log"

	"github.com/WangZhaoye/go-task-processor/internal/config"
	"github.com/WangZhaoye/go-task-processor/internal/model"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var DB *gorm.DB

func InitDB() {
	dsn := config.Cfg.DBUrl
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Fail to connect to DB %v", err)
	}

	err = db.AutoMigrate(&model.Task{})
	if err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	DB = db
	fmt.Println("✅ Connected to PostgreSQL and migrated schema.")
}

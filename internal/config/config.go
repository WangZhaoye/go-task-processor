package config

import (
	"github.com/spf13/viper"
    "log"
)

type Config struct {
	DBUrl string
	RedisAddr string
	RabbitMQUrl string
	Port string
}

var Cfg Config

func LoadConfig() {
	viper.SetConfigFile(".env")
	err := viper.ReadInConfig()
	if err != nil {
		log.Fatalf("Error reading config %v", err)
	}
	Cfg.DBUrl = viper.GetString("DATABASE_URL")
	Cfg.RedisAddr = viper.GetString("REDIS_ADDR")
	Cfg.RabbitMQUrl = viper.GetString("RABBITMQ_URL")
	Cfg.Port = viper.GetString("PORT")
}
package cache

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/redis/go-redis/v9"
)

var (
	RDB *redis.Client
	ctx = context.Background()
)

const (
	TaskCacheExpiration = 30 * time.Minute // 任务缓存过期时间
	TaskKeyPrefix       = "task:"          // 任务缓存key前缀
	TaskStatusPrefix    = "task_status:"   // 任务状态缓存key前缀
)

func InitRedis() {
	RDB = redis.NewClient(&redis.Options{
		Addr:     "localhost:6379",
		Password: "",
		DB:       0,
	})
	_, err := RDB.Ping(ctx).Result()
	if err != nil {
		log.Fatalf("❌ Failed to connect to Redis: %v", err)
	}

	log.Println("✅ Redis connected")
}

func SetIfNotExist(key string) bool {
	ok, err := RDB.SetNX(ctx, key, "1", time.Minute).Result()
	if err != nil {
		log.Printf("❌ Redis SetNX failed: %v", err)
		return false
	}
	return ok
}

// CacheTask 缓存任务数据
func CacheTask(taskID string, taskData interface{}) error {
	key := TaskKeyPrefix + taskID
	jsonData, err := json.Marshal(taskData)
	if err != nil {
		return err
	}

	err = RDB.Set(ctx, key, jsonData, TaskCacheExpiration).Err()
	if err != nil {
		log.Printf("❌ Failed to cache task %s: %v", taskID, err)
		return err
	}

	log.Printf("✅ Task %s cached successfully", taskID)
	return nil
}

// GetCachedTask 从缓存获取任务数据
func GetCachedTask(taskID string, target interface{}) (bool, error) {
	key := TaskKeyPrefix + taskID
	val, err := RDB.Get(ctx, key).Result()
	if err == redis.Nil {
		return false, nil // 缓存未命中
	}
	if err != nil {
		log.Printf("❌ Failed to get cached task %s: %v", taskID, err)
		return false, err
	}

	err = json.Unmarshal([]byte(val), target)
	if err != nil {
		log.Printf("❌ Failed to unmarshal cached task %s: %v", taskID, err)
		return false, err
	}

	log.Printf("✅ Task %s retrieved from cache", taskID)
	return true, nil
}

// InvalidateTaskCache 删除任务缓存
func InvalidateTaskCache(taskID string) error {
	key := TaskKeyPrefix + taskID
	err := RDB.Del(ctx, key).Err()
	if err != nil {
		log.Printf("❌ Failed to invalidate task cache %s: %v", taskID, err)
		return err
	}

	log.Printf("✅ Task cache %s invalidated", taskID)
	return nil
}

// CacheTaskStatus 缓存任务状态（用于快速状态查询）
func CacheTaskStatus(taskID string, status string) error {
	key := TaskStatusPrefix + taskID
	err := RDB.Set(ctx, key, status, TaskCacheExpiration).Err()
	if err != nil {
		log.Printf("❌ Failed to cache task status %s: %v", taskID, err)
		return err
	}

	log.Printf("✅ Task status %s cached: %s", taskID, status)
	return nil
}

// GetCachedTaskStatus 获取缓存的任务状态
func GetCachedTaskStatus(taskID string) (string, bool, error) {
	key := TaskStatusPrefix + taskID
	val, err := RDB.Get(ctx, key).Result()
	if err == redis.Nil {
		return "", false, nil // 缓存未命中
	}
	if err != nil {
		log.Printf("❌ Failed to get cached task status %s: %v", taskID, err)
		return "", false, err
	}

	log.Printf("✅ Task status %s retrieved from cache: %s", taskID, val)
	return val, true, nil
}

// BatchInvalidateCache 批量删除缓存（用于清理）
func BatchInvalidateCache(pattern string) error {
	keys, err := RDB.Keys(ctx, pattern).Result()
	if err != nil {
		return err
	}

	if len(keys) > 0 {
		err = RDB.Del(ctx, keys...).Err()
		if err != nil {
			log.Printf("❌ Failed to batch invalidate cache: %v", err)
			return err
		}
		log.Printf("✅ Batch invalidated %d cache keys", len(keys))
	}

	return nil
}

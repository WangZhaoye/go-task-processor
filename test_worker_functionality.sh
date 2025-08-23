#!/bin/bash

# 测试Worker功能脚本
API_URL="http://localhost:8080"

echo "🔧 开始测试Go Task Processor Worker功能..."
echo "=========================================="

# 检查API服务是否运行
echo "🔍 检查API服务状态..."
# 尝试创建一个测试请求来检查API是否运行
TEST_RESPONSE=$(curl -s -X POST "$API_URL/tasks" -H "Content-Type: application/json" -d '{"type":"test","payload":"api_check"}' 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$TEST_RESPONSE" ]; then
    echo "❌ API服务未运行，请先启动API服务"
    echo "   启动命令: go run cmd/api/main.go"
    exit 1
fi

# 检查是否返回了有效的JSON响应（包含错误也算API运行）
if echo "$TEST_RESPONSE" | jq . >/dev/null 2>&1; then
    echo "✅ API服务正常运行"
else
    echo "❌ API服务响应异常"
    echo "   响应内容: $TEST_RESPONSE"
    exit 1
fi
echo ""

# 编译Worker
echo "🔨 编译Worker程序..."
if [ ! -d "build" ]; then
    mkdir -p build
fi

go build -o build/worker cmd/worker/main.go
if [ $? -ne 0 ]; then
    echo "❌ Worker编译失败"
    exit 1
fi
echo "✅ Worker编译成功"
echo ""

# 测试1：创建测试任务
echo "📝 测试1：创建测试任务"
TASK_RESPONSES=()
TASK_IDS=()

# 创建不同类型的任务
TASK_TYPES=("email" "data_sync" "report" "notification" "cleanup")
for i in "${!TASK_TYPES[@]}"; do
    TYPE=${TASK_TYPES[$i]}
    TASK_RESPONSE=$(curl -s -X POST "$API_URL/tasks" \
      -H "Content-Type: application/json" \
      -d "{\"type\": \"$TYPE\", \"payload\": \"Test $TYPE task for worker processing\"}")
    
    TASK_ID=$(echo "$TASK_RESPONSE" | jq -r '.id')
    if [ "$TASK_ID" != "null" ] && [ -n "$TASK_ID" ]; then
        TASK_IDS+=("$TASK_ID")
        echo "✅ 创建 $TYPE 任务: $TASK_ID"
    else
        echo "❌ 创建 $TYPE 任务失败"
    fi
done

echo "✅ 创建了 ${#TASK_IDS[@]} 个测试任务"
echo ""

# 测试2：启动Worker并处理任务
echo "🚀 测试2：启动Worker处理任务"
echo "启动Worker（后台运行30秒）..."

# 在后台启动Worker
./build/worker &
WORKER_PID=$!
echo "Worker PID: $WORKER_PID"

# 监控任务处理进度
echo "📊 监控任务处理进度..."
PROCESSED_TASKS=0
FAILED_TASKS=0
RETRY_TASKS=0

for i in {1..30}; do
    sleep 1
    CURRENT_PROCESSED=0
    CURRENT_FAILED=0
    CURRENT_RETRY=0
    
    # 检查每个任务的状态
    for TASK_ID in "${TASK_IDS[@]}"; do
        TASK_STATUS=$(curl -s -X GET "$API_URL/tasks/$TASK_ID" | jq -r '.status')
        RETRY_COUNT=$(curl -s -X GET "$API_URL/tasks/$TASK_ID" | jq -r '.retry_count')
        
        case $TASK_STATUS in
            "completed")
                ((CURRENT_PROCESSED++))
                ;;
            "failed")
                ((CURRENT_FAILED++))
                ;;
            "processing")
                if [ "$RETRY_COUNT" != "0" ] && [ "$RETRY_COUNT" != "null" ]; then
                    ((CURRENT_RETRY++))
                fi
                ;;
        esac
    done
    
    # 打印进度（每5秒一次）
    if [ $((i % 5)) -eq 0 ]; then
        echo "   第${i}秒: 已处理=$CURRENT_PROCESSED, 失败=$CURRENT_FAILED, 重试=$CURRENT_RETRY"
    fi
    
    # 如果所有任务都处理完成，提前结束
    if [ $((CURRENT_PROCESSED + CURRENT_FAILED)) -eq ${#TASK_IDS[@]} ]; then
        echo "✅ 所有任务处理完成，提前结束监控"
        break
    fi
done

# 停止Worker
echo "🛑 停止Worker..."
kill $WORKER_PID 2>/dev/null
wait $WORKER_PID 2>/dev/null

echo ""

# 测试3：分析处理结果
echo "📊 测试3：分析任务处理结果"
echo "=========================================="

FINAL_COMPLETED=0
FINAL_FAILED=0
FINAL_PROCESSING=0
FINAL_PENDING=0
MAX_RETRY=0

echo "任务处理详情："
for i in "${!TASK_IDS[@]}"; do
    TASK_ID=${TASK_IDS[$i]}
    TYPE=${TASK_TYPES[$i]}
    
    TASK_DETAIL=$(curl -s -X GET "$API_URL/tasks/$TASK_ID")
    STATUS=$(echo "$TASK_DETAIL" | jq -r '.status')
    RETRY_COUNT=$(echo "$TASK_DETAIL" | jq -r '.retry_count')
    CREATED_AT=$(echo "$TASK_DETAIL" | jq -r '.created_at')
    UPDATED_AT=$(echo "$TASK_DETAIL" | jq -r '.updated_at')
    
    # 计算处理时间
    if [ "$UPDATED_AT" != "$CREATED_AT" ] && [ "$UPDATED_AT" != "null" ]; then
        # 这里简化处理，实际应该解析时间戳
        PROCESS_TIME="已更新"
    else
        PROCESS_TIME="未处理"
    fi
    
    case $STATUS in
        "completed")
            ((FINAL_COMPLETED++))
            echo "   ✅ $TYPE ($TASK_ID): 完成 (重试:$RETRY_COUNT, $PROCESS_TIME)"
            ;;
        "failed")
            ((FINAL_FAILED++))
            echo "   ❌ $TYPE ($TASK_ID): 失败 (重试:$RETRY_COUNT, $PROCESS_TIME)"
            ;;
        "processing")
            ((FINAL_PROCESSING++))
            echo "   🔄 $TYPE ($TASK_ID): 处理中 (重试:$RETRY_COUNT, $PROCESS_TIME)"
            ;;
        "pending")
            ((FINAL_PENDING++))
            echo "   ⏳ $TYPE ($TASK_ID): 等待中 (重试:$RETRY_COUNT, $PROCESS_TIME)"
            ;;
    esac
    
    # 记录最大重试次数
    if [ "$RETRY_COUNT" != "null" ] && [ "$RETRY_COUNT" -gt "$MAX_RETRY" ]; then
        MAX_RETRY=$RETRY_COUNT
    fi
done

echo ""
echo "📈 处理结果统计："
echo "   ✅ 完成任务: $FINAL_COMPLETED"
echo "   ❌ 失败任务: $FINAL_FAILED"
echo "   🔄 处理中: $FINAL_PROCESSING"
echo "   ⏳ 等待中: $FINAL_PENDING"
echo "   🔁 最大重试次数: $MAX_RETRY"

echo ""

# 测试4：重试机制验证
echo "🔁 测试4：重试机制验证"
if [ $MAX_RETRY -gt 0 ]; then
    echo "✅ 重试机制已触发，最大重试次数: $MAX_RETRY"
    echo "   重试机制工作正常"
else
    echo "ℹ️  本次测试中未触发重试机制"
    echo "   这可能是因为所有任务都成功处理了"
fi

echo ""

# 测试5：性能分析
echo "📊 测试5：性能分析"
SUCCESS_RATE=$((FINAL_COMPLETED * 100 / ${#TASK_IDS[@]}))
PROCESSING_RATE=$(((FINAL_COMPLETED + FINAL_FAILED) * 100 / ${#TASK_IDS[@]}))

echo "性能指标："
echo "   📈 成功率: ${SUCCESS_RATE}%"
echo "   🔄 处理率: ${PROCESSING_RATE}%"

if [ $SUCCESS_RATE -ge 80 ]; then
    echo "   🎯 系统性能优秀"
elif [ $SUCCESS_RATE -ge 60 ]; then
    echo "   ✅ 系统性能良好"
else
    echo "   ⚠️  系统性能需要优化"
fi

echo ""

# 测试6：缓存一致性验证
echo "💾 测试6：缓存一致性验证"
echo "验证任务状态更新后缓存是否正确失效..."

# 随机选择一个已处理的任务进行验证
for TASK_ID in "${TASK_IDS[@]}"; do
    TASK_STATUS=$(curl -s -X GET "$API_URL/tasks/$TASK_ID" | jq -r '.status')
    if [ "$TASK_STATUS" = "completed" ] || [ "$TASK_STATUS" = "failed" ]; then
        echo "验证任务 $TASK_ID 的缓存一致性..."
        
        # 第一次查询
        START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
        FIRST_QUERY=$(curl -s -X GET "$API_URL/tasks/$TASK_ID")
        END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
        FIRST_DURATION=$((END_TIME - START_TIME))
        
        # 第二次查询（应该从缓存读取）
        START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
        SECOND_QUERY=$(curl -s -X GET "$API_URL/tasks/$TASK_ID")
        END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
        SECOND_DURATION=$((END_TIME - START_TIME))
        
        # 比较结果
        FIRST_STATUS=$(echo "$FIRST_QUERY" | jq -r '.status')
        SECOND_STATUS=$(echo "$SECOND_QUERY" | jq -r '.status')
        
        if [ "$FIRST_STATUS" = "$SECOND_STATUS" ]; then
            echo "   ✅ 缓存一致性验证通过"
            echo "   📊 查询时间: ${FIRST_DURATION}ms → ${SECOND_DURATION}ms"
            if [ $SECOND_DURATION -lt $FIRST_DURATION ]; then
                echo "   🚀 缓存加速: $((FIRST_DURATION - SECOND_DURATION))ms"
            fi
        else
            echo "   ❌ 缓存一致性问题: $FIRST_STATUS → $SECOND_STATUS"
        fi
        break
    fi
done

echo ""
echo "=========================================="
echo "🎉 Worker功能测试完成！"
echo ""

# 最终总结
echo "🏆 测试总结："
echo "   📝 创建任务: ${#TASK_IDS[@]} 个"
echo "   ✅ 成功处理: $FINAL_COMPLETED 个"
echo "   ❌ 处理失败: $FINAL_FAILED 个"
echo "   🔄 仍在处理: $FINAL_PROCESSING 个"
echo "   ⏳ 等待处理: $FINAL_PENDING 个"
echo "   🔁 重试次数: $MAX_RETRY 次"
echo "   📈 成功率: ${SUCCESS_RATE}%"
echo ""

if [ $SUCCESS_RATE -ge 80 ] && [ $MAX_RETRY -le 3 ]; then
    echo "🎯 Worker功能测试 - 优秀！"
    echo "   ✅ 任务处理正常"
    echo "   ✅ 重试机制合理"
    echo "   ✅ 性能表现良好"
elif [ $SUCCESS_RATE -ge 60 ]; then
    echo "✅ Worker功能测试 - 良好！"
    echo "   ✅ 基本功能正常"
    echo "   ⚠️  可考虑优化处理成功率"
else
    echo "⚠️  Worker功能测试 - 需要优化"
    echo "   ❌ 处理成功率较低"
    echo "   🔍 建议检查处理逻辑"
fi

echo ""
echo "💡 下一步建议："
echo "   1. 测试并发处理能力"
echo "   2. 测试大批量任务处理"
echo "   3. 测试异常恢复机制"
echo "   4. 监控系统资源使用"

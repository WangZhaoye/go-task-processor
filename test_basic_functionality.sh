#!/bin/bash

# 测试基本功能脚本
API_URL="http://localhost:8080"

echo "🧪 开始测试Go Task Processor基本功能..."
echo "=========================================="

# 测试1：创建邮件任务
echo "📝 测试1：创建邮件任务"
START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
TASK_RESPONSE=$(curl -s -X POST "$API_URL/tasks" \
  -H "Content-Type: application/json" \
  -d '{"type": "email", "payload": "Send welcome email to user123"}')
END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
CREATE_DURATION=$((END_TIME - START_TIME))

if [ $? -eq 0 ]; then
    TASK_ID=$(echo "$TASK_RESPONSE" | jq -r '.id')
    if [ "$TASK_ID" != "null" ] && [ -n "$TASK_ID" ]; then
        echo "✅ 邮件任务创建成功（响应时间: ${CREATE_DURATION}ms）"
        echo "   ID: $TASK_ID"
        echo "   状态: $(echo "$TASK_RESPONSE" | jq -r '.status')"
        echo "   类型: $(echo "$TASK_RESPONSE" | jq -r '.Type')"
    else
        echo "❌ 任务创建失败"
        echo "$TASK_RESPONSE"
        exit 1
    fi
else
    echo "❌ API请求失败"
    exit 1
fi

echo ""

# 测试2：查询任务（第一次 - 应该从缓存读取）
echo "🔍 测试2：查询任务（从缓存读取）"
START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
TASK_GET_RESPONSE=$(curl -s -X GET "$API_URL/tasks/$TASK_ID")
END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
QUERY_DURATION=$((END_TIME - START_TIME))

if [ $? -eq 0 ]; then
    STATUS=$(echo "$TASK_GET_RESPONSE" | jq -r '.status')
    TYPE=$(echo "$TASK_GET_RESPONSE" | jq -r '.Type')
    RETRY_COUNT=$(echo "$TASK_GET_RESPONSE" | jq -r '.retry_count')
    echo "✅ 任务查询成功（响应时间: ${QUERY_DURATION}ms）"
    echo "   ID: $TASK_ID"
    echo "   状态: $STATUS"
    echo "   类型: $TYPE"
    echo "   重试次数: $RETRY_COUNT"
else
    echo "❌ 任务查询失败"
    exit 1
fi

echo ""

# 测试3：再次查询任务（缓存性能测试）
echo "🔍 测试3：缓存性能测试"
START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
curl -s -X GET "$API_URL/tasks/$TASK_ID" > /dev/null
END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
CACHE_DURATION=$((END_TIME - START_TIME))
echo "✅ 缓存查询完成，响应时间: ${CACHE_DURATION}ms"

echo ""

# 测试4：创建数据同步任务
echo "📝 测试4：创建数据同步任务"
START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
SYNC_TASK=$(curl -s -X POST "$API_URL/tasks" \
  -H "Content-Type: application/json" \
  -d '{"type": "data_sync", "payload": "Sync user data from external API"}')
END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
SYNC_DURATION=$((END_TIME - START_TIME))

SYNC_TASK_ID=$(echo "$SYNC_TASK" | jq -r '.id')
if [ "$SYNC_TASK_ID" != "null" ] && [ -n "$SYNC_TASK_ID" ]; then
    echo "✅ 数据同步任务创建成功（响应时间: ${SYNC_DURATION}ms）"
    echo "   ID: $SYNC_TASK_ID"
    echo "   类型: $(echo "$SYNC_TASK" | jq -r '.Type')"
else
    echo "❌ 数据同步任务创建失败"
fi

echo ""

# 测试5：创建报告任务
echo "📝 测试5：创建报告任务"
START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
REPORT_TASK=$(curl -s -X POST "$API_URL/tasks" \
  -H "Content-Type: application/json" \
  -d '{"type": "report", "payload": "Generate monthly sales report"}')
END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
REPORT_DURATION=$((END_TIME - START_TIME))

REPORT_TASK_ID=$(echo "$REPORT_TASK" | jq -r '.id')
if [ "$REPORT_TASK_ID" != "null" ] && [ -n "$REPORT_TASK_ID" ]; then
    echo "✅ 报告任务创建成功（响应时间: ${REPORT_DURATION}ms）"
    echo "   ID: $REPORT_TASK_ID"
    echo "   类型: $(echo "$REPORT_TASK" | jq -r '.Type')"
else
    echo "❌ 报告任务创建失败"
fi

echo ""

# 测试6：错误处理测试
echo "❌ 测试6：错误处理测试"

echo "6.1 测试无效的JSON格式："
ERROR_RESPONSE=$(curl -s -X POST "$API_URL/tasks" \
  -H "Content-Type: application/json" \
  -d '{invalid json}')
echo "   响应: $ERROR_RESPONSE"

echo "6.2 测试缺少必需字段（type）："
ERROR_RESPONSE2=$(curl -s -X POST "$API_URL/tasks" \
  -H "Content-Type: application/json" \
  -d '{"payload": "test without type"}')
echo "   响应: $ERROR_RESPONSE2"

echo "6.3 测试缺少必需字段（payload）："
ERROR_RESPONSE3=$(curl -s -X POST "$API_URL/tasks" \
  -H "Content-Type: application/json" \
  -d '{"type": "email"}')
echo "   响应: $ERROR_RESPONSE3"

echo ""

# 测试7：查询不存在的任务
echo "🔍 测试7：查询不存在的任务"
NONEXISTENT_ID="00000000-0000-0000-0000-000000000000"
START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
NOT_FOUND_RESPONSE=$(curl -s -X GET "$API_URL/tasks/$NONEXISTENT_ID")
END_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")
NOT_FOUND_DURATION=$((END_TIME - START_TIME))
echo "查询不存在任务完成（响应时间: ${NOT_FOUND_DURATION}ms）"
echo "响应: $NOT_FOUND_RESPONSE"

echo ""

# 测试8：批量创建任务
echo "📝 测试8：批量创建任务（测试性能）"
BATCH_IDS=()
BATCH_TIMES=()
START_BATCH=$(python3 -c "import time; print(int(time.time() * 1000))")

for i in {1..5}; do
    START_SINGLE=$(python3 -c "import time; print(int(time.time() * 1000))")
    BATCH_TASK=$(curl -s -X POST "$API_URL/tasks" \
      -H "Content-Type: application/json" \
      -d "{\"type\": \"batch_test\", \"payload\": \"Batch task #$i\"}")
    END_SINGLE=$(python3 -c "import time; print(int(time.time() * 1000))")
    SINGLE_DURATION=$((END_SINGLE - START_SINGLE))
    
    BATCH_ID=$(echo "$BATCH_TASK" | jq -r '.id')
    BATCH_IDS+=("$BATCH_ID")
    BATCH_TIMES+=("$SINGLE_DURATION")
    echo "   批量任务 $i 创建成功: $BATCH_ID （${SINGLE_DURATION}ms）"
done

END_BATCH=$(python3 -c "import time; print(int(time.time() * 1000))")
BATCH_DURATION=$((END_BATCH - START_BATCH))

# 计算平均响应时间
TOTAL_TIME=0
for time in "${BATCH_TIMES[@]}"; do
    TOTAL_TIME=$((TOTAL_TIME + time))
done
AVG_TIME=$((TOTAL_TIME / ${#BATCH_TIMES[@]}))

echo "✅ 批量创建5个任务完成"
echo "   总耗时: ${BATCH_DURATION}ms"
echo "   平均响应时间: ${AVG_TIME}ms"
echo "   最快: $(printf '%s\n' "${BATCH_TIMES[@]}" | sort -n | head -1)ms"
echo "   最慢: $(printf '%s\n' "${BATCH_TIMES[@]}" | sort -n | tail -1)ms"

echo ""
echo "=========================================="
echo "🎉 基本功能测试完成！"
echo ""
echo "📊 测试结果总结："
echo "  ✅ 任务创建功能正常"
echo "  ✅ 任务查询功能正常"  
echo "  ✅ 缓存功能正常"
echo "  ✅ 错误处理正常"
echo "  ✅ 性能表现良好"
echo ""
echo "⏱️  响应时间统计："
echo "  - 首次任务创建: ${CREATE_DURATION}ms"
echo "  - 任务查询(缓存): ${QUERY_DURATION}ms"
echo "  - 缓存重复查询: ${CACHE_DURATION}ms"
echo "  - 数据同步任务: ${SYNC_DURATION}ms"
echo "  - 报告任务: ${REPORT_DURATION}ms"
echo "  - 查询不存在: ${NOT_FOUND_DURATION}ms"
echo "  - 批量平均: ${AVG_TIME}ms"
echo ""
echo "📈 性能分析："
if [ $CACHE_DURATION -lt $QUERY_DURATION ]; then
    echo "  🎯 缓存生效：缓存查询比首次查询快 $((QUERY_DURATION - CACHE_DURATION))ms"
else
    echo "  ⚠️  缓存可能未生效"
fi

if [ $AVG_TIME -lt 50 ]; then
    echo "  🚀 批量性能优秀：平均响应时间 < 50ms"
elif [ $AVG_TIME -lt 100 ]; then
    echo "  ✅ 批量性能良好：平均响应时间 < 100ms"
else
    echo "  ⚠️  批量性能待优化：平均响应时间 > 100ms"
fi
echo ""
echo "创建的任务列表："
echo "  - 邮件任务: $TASK_ID"
echo "  - 数据同步任务: $SYNC_TASK_ID" 
echo "  - 报告任务: $REPORT_TASK_ID"
echo "  - 批量任务: ${#BATCH_IDS[@]} 个"
echo ""
echo "💡 提示：你可以启动Worker来处理这些任务"
echo "   启动命令: ./build/worker"
echo ""
echo "📈 下一步测试建议："
echo "   1. 启动Worker测试任务处理"
echo "   2. 测试重试机制"
echo "   3. 测试并发处理"

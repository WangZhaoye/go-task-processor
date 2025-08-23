#!/bin/bash

# 并发性能测试脚本
API_URL="http://localhost:8080"

echo "⚡ 开始Go Task Processor并发性能测试..."
echo "=========================================="

# 检查依赖
command -v jq >/dev/null 2>&1 || { echo "❌ 需要安装 jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ 需要安装 curl"; exit 1; }

# 检查API服务
echo "🔍 检查API服务状态..."
TEST_RESPONSE=$(curl -s -X POST "$API_URL/tasks" -H "Content-Type: application/json" -d '{"type":"test","payload":"api_check"}' 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$TEST_RESPONSE" ]; then
    echo "❌ API服务未运行，请先启动API服务"
    exit 1
fi

# 检查是否返回了有效的JSON响应（包含错误也算API运行）
if echo "$TEST_RESPONSE" | jq . >/dev/null 2>&1; then
    echo "✅ API服务正常运行"
else
    echo "❌ API服务响应异常，请检查服务状态"
    exit 1
fi
echo ""

# 测试参数配置
CONCURRENT_REQUESTS=10    # 并发请求数
TOTAL_TASKS=50           # 总任务数
BATCH_SIZE=5            # 每批任务数

# 测试1：并发创建任务
echo "📝 测试1：并发创建任务测试"
echo "配置: $CONCURRENT_REQUESTS 个并发, 总共 $TOTAL_TASKS 个任务"

# 创建临时文件存储结果
TEMP_DIR=$(mktemp -d)
RESULTS_FILE="$TEMP_DIR/concurrent_results.txt"
TASK_IDS_FILE="$TEMP_DIR/task_ids.txt"

# 并发创建任务的函数
create_task() {
    local task_num=$1
    local start_time=$(python3 -c "import time; print(int(time.time() * 1000))")
    
    local task_type="concurrent_test"
    local payload="Concurrent task #$task_num - $(date)"
    
    local response=$(curl -s -X POST "$API_URL/tasks" \
        -H "Content-Type: application/json" \
        -d "{\"type\": \"$task_type\", \"payload\": \"$payload\"}")
    
    local end_time=$(python3 -c "import time; print(int(time.time() * 1000))")
    local duration=$((end_time - start_time))
    
    local task_id=$(echo "$response" | jq -r '.id')
    local status_code=$?
    
    if [ "$task_id" != "null" ] && [ -n "$task_id" ] && [ $status_code -eq 0 ]; then
        echo "$task_num,$task_id,$duration,success" >> "$RESULTS_FILE"
        echo "$task_id" >> "$TASK_IDS_FILE"
    else
        echo "$task_num,null,$duration,failed" >> "$RESULTS_FILE"
    fi
}

# 开始并发测试
echo "🚀 开始并发创建任务..."
START_TOTAL=$(python3 -c "import time; print(int(time.time() * 1000))")

# 分批处理以避免过载
for ((batch=0; batch<$((TOTAL_TASKS/BATCH_SIZE)); batch++)); do
    echo "   处理第 $((batch+1)) 批 ($(((batch*BATCH_SIZE)+1))-$((((batch+1)*BATCH_SIZE))) )"
    
    # 启动并发进程
    for ((i=0; i<BATCH_SIZE; i++)); do
        task_num=$((batch*BATCH_SIZE + i + 1))
        create_task $task_num &
    done
    
    # 等待当前批次完成
    wait
    sleep 0.5  # 短暂休息避免过载
done

END_TOTAL=$(python3 -c "import time; print(int(time.time() * 1000))")
TOTAL_DURATION=$((END_TOTAL - START_TOTAL))

echo "✅ 并发创建完成，总耗时: ${TOTAL_DURATION}ms"
echo ""

# 分析并发创建结果
echo "📊 测试2：分析并发创建结果"
SUCCESSFUL_TASKS=$(grep "success" "$RESULTS_FILE" | wc -l | tr -d ' ')
FAILED_TASKS=$(grep "failed" "$RESULTS_FILE" | wc -l | tr -d ' ')
TOTAL_CREATED=$(wc -l < "$RESULTS_FILE" | tr -d ' ')

echo "创建结果统计："
echo "   ✅ 成功创建: $SUCCESSFUL_TASKS"
echo "   ❌ 创建失败: $FAILED_TASKS"
echo "   📊 总请求数: $TOTAL_CREATED"

if [ $SUCCESSFUL_TASKS -gt 0 ]; then
    # 计算响应时间统计
    SUCCESS_TIMES=$(grep "success" "$RESULTS_FILE" | cut -d',' -f3)
    
    MIN_TIME=$(echo "$SUCCESS_TIMES" | sort -n | head -1)
    MAX_TIME=$(echo "$SUCCESS_TIMES" | sort -n | tail -1)
    
    TOTAL_TIME=0
    COUNT=0
    for time in $SUCCESS_TIMES; do
        TOTAL_TIME=$((TOTAL_TIME + time))
        COUNT=$((COUNT + 1))
    done
    AVG_TIME=$((TOTAL_TIME / COUNT))
    
    echo ""
    echo "⏱️  响应时间分析："
    echo "   🏃 最快响应: ${MIN_TIME}ms"
    echo "   🐌 最慢响应: ${MAX_TIME}ms"
    echo "   📊 平均响应: ${AVG_TIME}ms"
    echo "   🎯 吞吐量: $(((SUCCESSFUL_TASKS * 1000) / TOTAL_DURATION)) 任务/秒"
    
    # 性能评估
    if [ $AVG_TIME -lt 100 ]; then
        echo "   🚀 并发性能优秀"
    elif [ $AVG_TIME -lt 200 ]; then
        echo "   ✅ 并发性能良好"
    else
        echo "   ⚠️  并发性能需要优化"
    fi
fi

echo ""

# 测试3：并发查询测试
echo "🔍 测试3：并发查询性能测试"

if [ $SUCCESSFUL_TASKS -gt 0 ]; then
    echo "测试并发查询性能..."
    
    QUERY_RESULTS_FILE="$TEMP_DIR/query_results.txt"
    QUERY_COUNT=20  # 并发查询数量
    
    # 并发查询函数
    query_task() {
        local query_num=$1
        local task_id=$(sed -n "${query_num}p" "$TASK_IDS_FILE")
        
        if [ -n "$task_id" ]; then
            local start_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            local response=$(curl -s -X GET "$API_URL/tasks/$task_id")
            local end_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            local duration=$((end_time - start_time))
            
            local status=$(echo "$response" | jq -r '.status' 2>/dev/null)
            if [ "$status" != "null" ] && [ -n "$status" ]; then
                echo "$query_num,$task_id,$duration,success,$status" >> "$QUERY_RESULTS_FILE"
            else
                echo "$query_num,$task_id,$duration,failed,null" >> "$QUERY_RESULTS_FILE"
            fi
        fi
    }
    
    # 开始并发查询
    START_QUERY=$(python3 -c "import time; print(int(time.time() * 1000))")
    
    for ((i=1; i<=QUERY_COUNT && i<=SUCCESSFUL_TASKS; i++)); do
        query_task $i &
    done
    
    wait
    END_QUERY=$(python3 -c "import time; print(int(time.time() * 1000))")
    QUERY_TOTAL_DURATION=$((END_QUERY - START_QUERY))
    
    # 分析查询结果
    SUCCESSFUL_QUERIES=$(grep "success" "$QUERY_RESULTS_FILE" | wc -l | tr -d ' ')
    
    if [ $SUCCESSFUL_QUERIES -gt 0 ]; then
        QUERY_TIMES=$(grep "success" "$QUERY_RESULTS_FILE" | cut -d',' -f3)
        
        QUERY_MIN=$(echo "$QUERY_TIMES" | sort -n | head -1)
        QUERY_MAX=$(echo "$QUERY_TIMES" | sort -n | tail -1)
        
        QUERY_TOTAL=0
        for time in $QUERY_TIMES; do
            QUERY_TOTAL=$((QUERY_TOTAL + time))
        done
        QUERY_AVG=$((QUERY_TOTAL / SUCCESSFUL_QUERIES))
        
        echo "✅ 并发查询完成:"
        echo "   🎯 成功查询: $SUCCESSFUL_QUERIES"
        echo "   ⏱️  平均响应: ${QUERY_AVG}ms"
        echo "   🏃 最快查询: ${QUERY_MIN}ms"
        echo "   🐌 最慢查询: ${QUERY_MAX}ms"
        echo "   📈 查询吞吐量: $(((SUCCESSFUL_QUERIES * 1000) / QUERY_TOTAL_DURATION)) 查询/秒"
    fi
else
    echo "⚠️  没有成功创建的任务，跳过查询测试"
fi

echo ""

# 测试4：缓存命中率测试
echo "💾 测试4：缓存性能测试"

if [ $SUCCESSFUL_TASKS -gt 0 ]; then
    echo "测试缓存命中率和性能..."
    
    # 选择几个任务进行重复查询
    TEST_TASKS=($(head -5 "$TASK_IDS_FILE"))
    CACHE_TEST_RESULTS="$TEMP_DIR/cache_results.txt"
    
    for task_id in "${TEST_TASKS[@]}"; do
        if [ -n "$task_id" ]; then
            # 第一次查询（可能需要从数据库读取）
            start_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            curl -s -X GET "$API_URL/tasks/$task_id" > /dev/null
            end_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            first_duration=$((end_time - start_time))
            
            # 第二次查询（应该从缓存读取）
            start_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            curl -s -X GET "$API_URL/tasks/$task_id" > /dev/null
            end_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            second_duration=$((end_time - start_time))
            
            # 第三次查询（确认缓存稳定性）
            start_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            curl -s -X GET "$API_URL/tasks/$task_id" > /dev/null
            end_time=$(python3 -c "import time; print(int(time.time() * 1000))")
            third_duration=$((end_time - start_time))
            
            echo "$first_duration,$second_duration,$third_duration" >> "$CACHE_TEST_RESULTS"
        fi
    done
    
    if [ -f "$CACHE_TEST_RESULTS" ] && [ -s "$CACHE_TEST_RESULTS" ]; then
        echo "📊 缓存性能分析:"
        
        total_first=0
        total_second=0
        total_third=0
        count=0
        
        while IFS=',' read -r first second third; do
            total_first=$((total_first + first))
            total_second=$((total_second + second))
            total_third=$((total_third + third))
            count=$((count + 1))
        done < "$CACHE_TEST_RESULTS"
        
        if [ $count -gt 0 ]; then
            avg_first=$((total_first / count))
            avg_second=$((total_second / count))
            avg_third=$((total_third / count))
            
            echo "   🔍 首次查询平均: ${avg_first}ms"
            echo "   💾 缓存查询平均: ${avg_second}ms"
            echo "   🔄 重复查询平均: ${avg_third}ms"
            
            if [ $avg_second -lt $avg_first ]; then
                improvement=$((avg_first - avg_second))
                improvement_pct=$(((improvement * 100) / avg_first))
                echo "   🚀 缓存提升: ${improvement}ms (${improvement_pct}%)"
            fi
        fi
    fi
fi

echo ""

# 清理临时文件
rm -rf "$TEMP_DIR"

echo "=========================================="
echo "🎉 并发性能测试完成！"
echo ""

# 最终性能报告
echo "🏆 性能测试总结:"
echo "   📝 任务创建:"
echo "     - 并发数: $CONCURRENT_REQUESTS"
echo "     - 成功率: $(((SUCCESSFUL_TASKS * 100) / TOTAL_TASKS))%"
if [ $SUCCESSFUL_TASKS -gt 0 ]; then
    echo "     - 平均响应: ${AVG_TIME}ms"
    echo "     - 吞吐量: $(((SUCCESSFUL_TASKS * 1000) / TOTAL_DURATION)) 任务/秒"
fi

if [ -n "$QUERY_AVG" ]; then
    echo "   🔍 任务查询:"
    echo "     - 查询成功率: $(((SUCCESSFUL_QUERIES * 100) / QUERY_COUNT))%"
    echo "     - 平均响应: ${QUERY_AVG}ms"
    echo "     - 查询吞吐量: $(((SUCCESSFUL_QUERIES * 1000) / QUERY_TOTAL_DURATION)) 查询/秒"
fi

echo ""

# 性能评级
OVERALL_PERFORMANCE="优秀"
if [ $SUCCESSFUL_TASKS -lt $((TOTAL_TASKS * 8 / 10)) ]; then
    OVERALL_PERFORMANCE="需要优化"
elif [ $SUCCESSFUL_TASKS -lt $((TOTAL_TASKS * 9 / 10)) ]; then
    OVERALL_PERFORMANCE="良好"
fi

if [ -n "$AVG_TIME" ] && [ $AVG_TIME -gt 200 ]; then
    OVERALL_PERFORMANCE="需要优化"
elif [ -n "$AVG_TIME" ] && [ $AVG_TIME -gt 100 ]; then
    if [ "$OVERALL_PERFORMANCE" = "优秀" ]; then
        OVERALL_PERFORMANCE="良好"
    fi
fi

echo "🎯 系统并发性能: $OVERALL_PERFORMANCE"
echo ""
echo "💡 优化建议:"
if [ "$OVERALL_PERFORMANCE" = "需要优化" ]; then
    echo "   - 考虑增加连接池大小"
    echo "   - 优化数据库查询性能"
    echo "   - 检查系统资源使用情况"
    echo "   - 考虑使用负载均衡"
elif [ "$OVERALL_PERFORMANCE" = "良好" ]; then
    echo "   - 系统表现良好，可考虑进一步优化缓存策略"
    echo "   - 监控生产环境性能表现"
else
    echo "   - 系统性能优秀，维持当前配置"
    echo "   - 可以考虑提高并发处理能力"
fi

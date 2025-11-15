import requests
import json
import socket
import time

# 检查网络连通性
def check_network(host, port):
    try:
        socket.create_connection((host, port), timeout=5)
        print(f"DEBUG: 网络连通性检查: {host}:{port} 可达")
        return True
    except socket.error as e:
        print(f"ERROR: 网络连通性检查失败: {host}:{port}, error={e}")
        return False

def get_player_status(cmd, host_ip, host_port, player_id, retries=3, delay=2):
    """
    获取播放器状态（带重试）
    cmd: 命令列表，例如 ["power", "?"]
    host_ip: LMS 服务器 IP
    host_port: LMS 服务器端口
    player_id: 播放器 ID
    返回: (error, result) - error 为 None 表示成功，否则为错误信息；result 为响应数据或 None
    """
    url = f'http://{host_ip}:{host_port}/jsonrpc.js'
    headers = {'Content-Type': 'application/json'}
    data = {"id": 1, "method": "slim.request", "params": [player_id, cmd]}
    
    for attempt in range(retries):
        print(f"DEBUG: 尝试 {attempt + 1}/{retries}: url={url}, cmd={cmd}, player_id={player_id}, data={json.dumps(data)}")
        try:
            response = requests.post(url, headers=headers, json=data, timeout=10)
            print(f"DEBUG: HTTP 响应头: status_code={response.status_code}, headers={response.headers}")
            response.raise_for_status()
            response_json = response.json()
            print(f"DEBUG: JSON 响应: {json.dumps(response_json, indent=2)}")
            return None, response_json
        except requests.exceptions.Timeout:
            print(f"ERROR: 尝试 {attempt + 1} 超时: url={url}, cmd={cmd}")
            if attempt < retries - 1:
                time.sleep(delay)
            continue
        except requests.exceptions.HTTPError as e:
            print(f"ERROR: 尝试 {attempt + 1} HTTP错误: url={url}, cmd={cmd}, status_code={e.response.status_code}")
            if attempt < retries - 1:
                time.sleep(delay)
            continue
        except requests.exceptions.ConnectionError as e:
            print(f"ERROR: 尝试 {attempt + 1} 连接错误: url={url}, cmd={cmd}, error={str(e)}")
            check_network(host_ip, host_port)
            if attempt < retries - 1:
                time.sleep(delay)
            continue
        except requests.exceptions.RequestException as e:
            print(f"ERROR: 尝试 {attempt + 1} 请求异常: url={url}, cmd={cmd}, error={str(e)}")
            if attempt < retries - 1:
                time.sleep(delay)
            continue
        except ValueError as e:
            print(f"ERROR: 尝试 {attempt + 1} 响应解析错误: url={url}, cmd={cmd}, error={str(e)}")
            if attempt < retries - 1:
                time.sleep(delay)
            continue
    # 尝试备用命令测试
    print(f"DEBUG: 尝试备用命令: serverstatus")
    data = {"id": 1, "method": "slim.request", "params": ["-", ["serverstatus", 0, 999]]}
    try:
        response = requests.post(url, headers=headers, json=data, timeout=10)
        print(f"DEBUG: 备用命令 HTTP 响应头: status_code={response.status_code}, headers={response.headers}")
        response.raise_for_status()
        response_json = response.json()
        print(f"DEBUG: 备用命令 JSON 响应: {json.dumps(response_json, indent=2)}")
    except Exception as e:
        print(f"ERROR: 备用命令失败: {str(e)}")
    return f"Error: Failed after {retries} attempts", None

def extract_result_field(result, field, default="N/A"):
    """
    从响应中提取指定字段
    result: 响应数据（字典）
    field: 要提取的字段名
    default: 默认值
    """
    if not isinstance(result, dict):
        print(f"ERROR: extract_result_field: result 不是字典, result={result}")
        return default
    
    result_dict = result.get('result', {})
    if not isinstance(result_dict, dict):
        print(f"ERROR: extract_result_field: result['result'] 不是字典, result={result}")
        return default
    
    value = result_dict.get(field, default)
    print(f"DEBUG: 提取字段: field={field}, value={value}, default={default}")
    return value

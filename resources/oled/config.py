import configparser
import os
import logging
import subprocess

CONFIG_FILE = "oled.ini"

def get_mac_address():
    """获取 eth0 的 MAC 地址作为 PLAYER_ID"""
    try:
        # 读取 /sys/class/net/eth0/address
        with open('/sys/class/net/eth0/address', 'r') as f:
            mac = f.read().strip()
            logging.info(f"从 eth0 获取 MAC 地址: {mac}")
            return mac
    except FileNotFoundError:
        logging.warning("eth0 网卡不存在，尝试其他网卡...")
        
        # 尝试获取第一个非 lo 网卡的 MAC
        try:
            result = subprocess.run(
                ['ip', 'link', 'show'],
                capture_output=True,
                text=True,
                check=True
            )
            
            for line in result.stdout.split('\n'):
                if 'link/ether' in line:
                    mac = line.split()[1]
                    logging.info(f"从其他网卡获取 MAC 地址: {mac}")
                    return mac
        except Exception as e:
            logging.error(f"无法获取 MAC 地址: {e}")
    
    except Exception as e:
        logging.error(f"读取 MAC 地址失败: {e}")
    
    return None

def load_config():
    """加载配置文件"""
    
    # 检查配置文件是否存在
    if not os.path.exists(CONFIG_FILE):
        logging.error(f"错误：未找到配置文件 {CONFIG_FILE}")
        logging.error("请创建配置文件并填写 LMS 服务器信息")
        exit(1)
    
    # 读取配置
    config = configparser.ConfigParser()
    
    try:
        config.read(CONFIG_FILE)
    except Exception as e:
        logging.error(f"配置文件读取失败: {e}")
        exit(1)
    
    # 读取 LMS 服务器配置
    try:
        host_ip = config.get("SERVER", "HOST_IP")
        host_port = config.get("SERVER", "HOST_Port")
        
        # PLAYER_ID 优先从配置文件读取，否则自动获取 MAC
        try:
            player_id = config.get("SERVER", "PLAYER_ID")
            if not player_id or player_id.strip() == "":
                player_id = None
        except (configparser.NoSectionError, configparser.NoOptionError):
            player_id = None
        
        # 如果配置文件中没有 PLAYER_ID，自动获取
        if player_id is None:
            logging.info("配置文件中未找到 PLAYER_ID，尝试自动获取...")
            player_id = get_mac_address()
            
            if player_id is None:
                logging.error("无法自动获取 PLAYER_ID (MAC 地址)")
                logging.error("请在配置文件中手动指定 PLAYER_ID")
                exit(1)
        
        # 验证配置
        if not host_ip or not host_port:
            logging.error("配置不完整，请检查 oled.ini")
            logging.error("需要: [SERVER] HOST_IP 和 HOST_Port")
            exit(1)
        
        logging.info(f"配置加载成功: LMS={host_ip}:{host_port}, Player={player_id}")
        return host_ip, host_port, player_id
        
    except (configparser.NoSectionError, configparser.NoOptionError) as e:
        logging.error(f"配置文件格式无效: {e}")
        logging.error("请确保配置文件包含 [SERVER] 部分")
        exit(1)

# 测试代码
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    print("=== 配置加载测试 ===")
    host_ip, host_port, player_id = load_config()
    print(f"LMS 服务器: {host_ip}:{host_port}")
    print(f"播放器 ID: {player_id}")

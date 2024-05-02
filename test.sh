#!/bin/bash

# Обновление системы
echo "Обновление списка пакетов и установленных программ..."
sudo apt-get update && sudo apt-get upgrade -y

# Установка и настройка UFW
echo "Установка и настройка брандмауэра UFW..."
sudo apt-get install ufw -y
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# Проверка текущего порта SSH
current_ssh_port=$(sudo grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
if [[ -z "$current_ssh_port" ]]; then
    current_ssh_port=22 # Предположим, что используется стандартный порт, если порт не найден
fi
echo "Текущий порт SSH: $current_ssh_port"

# Запрос нового порта для SSH от пользователя
echo "Введите новый порт для SSH (1024-65535):"
while true; do
    read -p "Новый порт SSH: " ssh_port
    if [[ "$ssh_port" =~ ^[0-9]+$ ]] && [ "$ssh_port" -ge 1024 ] && [ "$ssh_port" -le 65535 ]; then
        echo "Новый порт $ssh_port выбран для SSH."
        sudo sed -i "s/Port $current_ssh_port/Port $ssh_port/" /etc/ssh/sshd_config
        sudo ufw allow $ssh_port/tcp
        sudo ufw delete allow $current_ssh_port/tcp
        sudo service ssh restart
        break
    else
        echo "Ошибка: введите корректный порт (число от 1024 до 65535)."
    fi
done

# Функция создания пользователя
create_user() {
    echo "Правила для пароля: минимум 12 символов, включая хотя бы одну заглавную букву, одну строчную букву, одну цифру и один специальный символ."
    while true; do
        read -p "Введите имя нового пользователя: " username
        if [[ "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
            if ! id "$username" &>/dev/null; then
                echo "Хотите ли вы создать пользователя с возможностью выполнения команд sudo без пароля? [y/N]"
                read -p "Введите y для да или n для нет: " sudo_without_pass
                while true; do
                    read -s -p "Введите пароль: " password
                    echo
                    read -s -p "Подтвердите пароль: " password_confirm
                    echo
                    if [ "$password" == "$password_confirm" ]; then
                        if [[ ${#password} -ge 12 && "$password" =~ [A-Z] && "$password" =~ [a-z] && "$password" =~ [0-9] && "$password" =~ [^a-zA-Z0-9] ]]; then
                            sudo useradd -m -s /bin/bash "$username"
                            echo "$username:$password" | sudo chpasswd
                            if [[ "$sudo_without_pass" =~ ^[Yy]$ ]]; then
                                echo "$username ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$username
                            else
                                sudo usermod -aG sudo "$username"
                            fi
                            echo "Пользователь $username создан."
                            break
                        else
                            echo "Пароль не соответствует требованиям безопасности."
                        fi
                    else
                        echo "Пароли не совпадают. Пожалуйста, попробуйте ещё раз."
                    fi
                done
                break
            else
                echo "Пользователь уже существует. Пожалуйста, выберите другое имя."
            fi
        else
            echo "Имя пользователя может содержать только латинские буквы, цифры и подчеркивания."
        fi
    done
}

# Цикл создания пользователей
while true; do
    create_user
    read -p "Хотите создать ещё одного пользователя? [y/N]: " add_another
    if ! [[ "$add_another" =~ ^[Yy]$ ]]; then
        break
    fi
done

# Запрет SSH входа для root
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo service ssh restart

# Установка и настройка Fail2Ban
echo "Установка Fail2Ban..."
sudo apt-get install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Конфигурация Fail2Ban для защиты SSH на нестандартном порту
echo "Настройка Fail2Ban для нового порта SSH..."
sudo bash -c "cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port    = $ssh_port
filter  = sshd
logpath = /var/log/auth.log
maxretry = 5
EOF"

# Перезагрузка Fail2Ban
sudo systemctl restart fail2ban

echo "Базовая настройка безопасности завершена."

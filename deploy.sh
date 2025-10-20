#!/bin/bash
read -p "Git Repository URL" REPO_URL
read -p "Personal Access Token (PAT)" PAT
read -p "Branch name [main]: " BRANCH
BRANCH=${BRANCH:-main}
echo "Remote server SSH details:"
read -p "-> Username" USERNAME
read -p "-> Server IP address" IP_ADDRESS
read -p "-> SSH key path" SSH_KEY_PATH
read -p "Application port (internal container port)" PORT
if git ls-remote -h "$REPO_URL" &> /dev/null; then
  git pull origin "$BRANCH"
else
  git clone "$REPO_URL"
fi
git checkout "$BRANCH"
cd "$(basename "$REPO_URL" .git)" || exit
if [ -f "Dockerfile" ] && [ -f "docker-compose.yml" ]; then
  echo "Building and deploying..."
  ssh "$USERNAME"@"$IP_ADDRESS" "mkdir -p /home/$USERNAME/app"
  #Check and Install Docker
  if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker "$USERNAME"
    rm get-docker.sh
  else
    echo "Docker found."
  fi
  # Check and Install Docker Compose
  if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose not found. Installing..."
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  else
    echo "Docker Compose found."
  fi

  # Check and Install NGINX
  if ! command -v nginx &> /dev/null; then
    echo "NGINX not found. Installing..."
    sudo apt update
    sudo apt install nginx -y
  else
    echo "NGINX found."
  fi
  # Check if user is already in docker group
  if ! groups $USER | grep -q '\bdocker\b'; then
      echo "Adding user to docker group..."
      sudo usermod -aG docker $USER
      echo "User added to docker group. Please log out and log back in to apply changes."
  else
      echo "User is already in docker group"
  fi
  # Enable and start Docker service
  sudo systemctl enable docker
  sudo systemctl start docker

  # Enable and start NGINX service
  sudo systemctl enable nginx
  sudo systemctl start nginx

  # Check service status
  echo "Checking service status..."
  echo "Docker status:"
  sudo systemctl is-active docker
  sudo systemctl is-enabled docker

  echo "NGINX status:"
  sudo systemctl is-active nginx
  sudo systemctl is-enabled nginx

  # Check installed versions
  echo "Checking installed versions..."

  echo -n "Docker version: "
  docker --version

  echo -n "Docker Compose version: "
  docker-compose --version

  echo -n "NGINX version: "
  nginx -v 2>&1

  # Additional Docker system information
  echo -e "\nDocker System Info:"
  docker system info

  scp -i "$SSH_KEY_PATH" -r . "$USERNAME"@"$IP_ADDRESS":/home/$USERNAME/app
  cd /home/$USERNAME/app
  docker build -t myapp . && docker-compose up -d
  if [ $? -eq 0 ]; then
    echo "Deployment successful."
  else
    echo "Deployment failed."
  fi
  # Check if application is accessible on the specified port
  echo "Checking application accessibility on port $PORT..."

  # Check if port is listening
  if netstat -tuln | grep -q ":$PORT "; then
      echo "Port $PORT is listening"

      # Test local connection
      if curl -s "http://localhost:$PORT" > /dev/null; then
          echo "Application is accessible locally on port $PORT"
      else
          echo "Warning: Application is not responding locally on port $PORT"
      fi

      # Test external connection if public IP is available
      PUBLIC_IP=$(curl -s ifconfig.me)
      if [ -n "$PUBLIC_IP" ]; then
          if curl -s "http://$PUBLIC_IP:$PORT" > /dev/null; then
              echo "Application is accessible externally on port $PORT"
          else
              echo "Warning: Application is not accessible externally on port $PORT"
          fi
      fi
  else
      echo "Error: Port $PORT is not listening"
  fi
fi

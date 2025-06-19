FROM node:18-alpine

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем package.json и package-lock.json
COPY package*.json ./

# Устанавливаем все зависимости (и dev, и prod)
RUN npm install

# Копируем исходный код
COPY . .

# Делаем скрипт исполняемым
# RUN chmod +x /app/scripts/generate_config.sh

# Собираем TypeScript в JavaScript
RUN npm run build

# Удаляем dev-зависимости для уменьшения размера образа
RUN npm prune --production

# Указываем порт (если ваш сервер слушает другой порт, измените здесь)
EXPOSE 5000

# Запускаем сервер
CMD ["node", "dist/index.js"] 
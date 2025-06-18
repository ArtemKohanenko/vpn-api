FROM node:18-alpine

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем package.json и package-lock.json
COPY package*.json ./

# Устанавливаем зависимости
RUN npm install --production

# Копируем исходный код
COPY . .

# Собираем TypeScript в JavaScript
RUN npm run build

# Указываем порт (если ваш сервер слушает другой порт, измените здесь)
EXPOSE 3000

# Запускаем сервер
CMD ["node", "dist/index.js"] 
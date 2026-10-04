# ============================================================
# Bài tập 2: Dockerfile - Payment Service
# Đóng gói Spring Boot Microservice thành Docker Image
# ============================================================

# 1. Chọn base image chứa JRE 17 gọn nhẹ (Alpine Linux ~85MB)
FROM eclipse-temurin:17-jre-alpine

# 2. Tạo thư mục làm việc trong container
WORKDIR /app

# 3. Copy file jar từ thư mục build của Gradle vào container
COPY build/libs/payment-service-1.0.0.jar app.jar

# 4. Mở port 8080 để giao tiếp với các microservices khác
EXPOSE 8080

# 5. Lệnh khởi chạy ứng dụng Spring Boot
ENTRYPOINT ["java", "-jar", "app.jar"]

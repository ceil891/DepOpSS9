# SS9 - CI/CD Pipeline & Docker Microservices

> **Môn học:** DevOps  
> **Chủ đề:** CI/CD Pipeline GitLab, Container hóa ứng dụng Spring Boot

---

## 📁 Cấu trúc thư mục

```
ss9/
├── bai1/                          # Bài 1: Khắc phục lỗi CI/CD cơ bản
│   ├── .gitlab-ci.yml             # File CI đã sửa hoàn chỉnh
│   └── giai-thich-loi.md          # Phân tích và giải thích lỗi
│
├── bai2/                          # Bài 2: Container hóa Spring Boot
│   └── Dockerfile                 # Dockerfile cho Payment Service
│
├── bai3/                          # Bài 3: Pipeline CI/CD + PostgreSQL
│   └── .gitlab-ci.yml             # Pipeline 2 stages: test → build
│
└── bai4/                          # Bài 4: Push Docker Image lên Docker Hub
    └── .gitlab-ci.yml             # Pipeline 3 stages: test → build → dockerize
```

---

## 📝 Tóm tắt từng bài

### Bài 1 — Khắc phục lỗi Pipeline CI/CD cơ bản

**Các lỗi phát hiện:**
1. ❌ `stages:` thiếu dấu `-` → sai cú pháp YAML mảng
2. ❌ Thiếu `image:` → không có môi trường Java/Gradle → lỗi "command not found"

**Giải pháp:**
- Sửa `stages:` thành list YAML đúng chuẩn
- Thêm `image: gradle:7.6-jdk17` để có môi trường Java

---

### Bài 2 — Container hóa Spring Boot với Dockerfile

**Các keyword Dockerfile sử dụng:**

| Keyword | Chức năng |
|---------|-----------|
| `FROM` | Chọn base image (eclipse-temurin:17-jre-alpine) |
| `WORKDIR` | Đặt thư mục làm việc trong container (/app) |
| `COPY` | Copy file .jar vào container |
| `EXPOSE` | Khai báo port 8080 |
| `ENTRYPOINT` | Lệnh khởi chạy ứng dụng |

---

### Bài 3 — Pipeline CI/CD kết nối PostgreSQL

**Pipeline gồm 2 stages:**
- **test**: Dùng `services: postgres:14-alpine`, chạy `./gradlew test`
- **build**: Chạy `./gradlew build -x test`, lưu `artifacts` với `expire_in: 1 day`

---

### Bài 4 — Push Docker Image lên Docker Hub

**Pipeline gồm 3 stages:** `test → build → dockerize`

**Bảo mật thông tin đăng nhập:**
- Dùng GitLab CI/CD Variables: `$DOCKER_USERNAME`, `$DOCKER_PASSWORD`
- **Không hard-code** username/password vào file YAML
- Dùng Docker-in-Docker (DinD) với `image: docker:latest` + `services: docker:dind`

**Cách thiết lập Variables trên GitLab:**
```
GitLab Project → Settings → CI/CD → Variables → Add variable
  - DOCKER_USERNAME = <your-dockerhub-username>
  - DOCKER_PASSWORD = <your-dockerhub-access-token>  (Protected + Masked)
```

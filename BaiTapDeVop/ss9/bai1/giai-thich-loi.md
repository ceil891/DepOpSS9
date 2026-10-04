# Bài tập 1: Phân tích & Khắc phục lỗi Pipeline CI/CD cơ bản

## 📋 File .gitlab-ci.yml bị lỗi (ban đầu)

```yaml
stages:
  build_app

build_job:
  stage: build_app
  script:
    - ./gradlew clean build -x test
```

---

## 🔍 Phân tích lỗi

### Lỗi 1: Sai cú pháp khai báo mảng `stages`

**Vị trí lỗi:** Khối `stages`

**Mô tả:**
```yaml
# ❌ SAI - đây là cú pháp scalar (chuỗi đơn), không phải mảng YAML
stages:
  build_app
```

Trong YAML, một **mảng (list/array)** phải được khai báo bằng dấu gạch đầu dòng (`-`) trước mỗi phần tử:

```yaml
# ✅ ĐÚNG - khai báo mảng đúng cú pháp YAML
stages:
  - build_app
```

**Hậu quả:** GitLab CI/CD Parser sẽ đọc `stages` như một scalar string thay vì một list, dẫn đến lỗi validation và pipeline không thể khởi chạy, báo lỗi `jobs:build_job:stage config should be a string`.

---

### Lỗi 2: Thiếu khai báo `image` — Không có môi trường Java/Gradle

**Vị trí lỗi:** Job `build_job` thiếu keyword `image`

**Mô tả:**
Lệnh `./gradlew clean build -x test` yêu cầu:
- **JDK (Java Development Kit)** để biên dịch mã Java/Kotlin.
- **Gradle Wrapper** hoặc môi trường có Gradle để thực thi.

GitLab Runner mặc định sử dụng **shell executor** hoặc một Docker image rất tối giản (thường là `ruby:latest` hoặc image hệ thống không có Java). Khi không khai báo `image`, Runner sẽ chạy trong môi trường không có Java, dẫn đến lỗi:

```
bash: ./gradlew: Permission denied
# hoặc
/bin/sh: java: not found
# hoặc
Error: Could not find or load main class org.gradle.wrapper.GradleWrapperMain
```

**Hậu quả:** Pipeline báo lỗi **"command not found"** ngay từ bước khởi tạo vì không tìm thấy Java runtime để chạy Gradle Wrapper.

**Giải pháp:** Thêm `image: gradle:7.6-jdk17` hoặc image tương đương chứa sẵn JDK 17 và Gradle.

---

## ✅ Tóm tắt các điểm lỗi/thiếu sót

| # | Vị trí | Lỗi | Mức độ |
|---|--------|-----|--------|
| 1 | `stages:` | Thiếu dấu `-` → sai cú pháp YAML mảng | 🔴 Critical |
| 2 | `build_job:` | Thiếu `image:` → không có môi trường Java/Gradle | 🔴 Critical |

---

## 📄 File .gitlab-ci.yml sau khi sửa

Xem file [.gitlab-ci.yml](./.gitlab-ci.yml) đã được sửa hoàn chỉnh.

---

## 📚 Giải thích các keyword được sử dụng

| Keyword | Ý nghĩa |
|---------|---------|
| `stages` | Định nghĩa danh sách các giai đoạn (stage) của pipeline, thực thi theo thứ tự từ trên xuống |
| `image` | Chỉ định Docker image dùng làm môi trường thực thi cho job. Image phải chứa đầy đủ công cụ cần thiết |
| `stage` | Gán job vào một stage đã được khai báo trong `stages` |
| `script` | Danh sách các lệnh shell sẽ được thực thi tuần tự bên trong container |

---

## 💡 Lưu ý thêm

- **`gradle:7.6-jdk17`**: Image chính thức của Gradle trên Docker Hub, tích hợp sẵn JDK 17 và Gradle 7.6 — đủ để chạy `./gradlew` mà không cần cài thêm gì.
- **`-x test`**: Flag bỏ qua các unit test khi build, giúp tăng tốc quá trình CI trong bài tập này.
- **`clean`**: Xóa toàn bộ output build cũ trước khi build mới, đảm bảo build sạch (clean build).

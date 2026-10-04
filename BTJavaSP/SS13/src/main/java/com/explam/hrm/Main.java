package com.explam.ss13;




import com.example.hrm.model.User;
import com.example.hrm.repository.UserRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.security.crypto.password.PasswordEncoder;

@SpringBootApplication
public class Main {

    public static void main(String[] args) {
        SpringApplication.run(HrmApplication.class, args);
    }

    // Tự động thêm tài khoản mẫu vào Database ngay khi ứng dụng khởi động thành công
    @Bean
    public CommandLineRunner initData(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        return args -> {
            // Kiểm tra tránh trùng lặp dữ liệu khi khởi động lại
            if (userRepository.findByUsername("admin").isEmpty()) {
                // Tạo tài khoản có username: admin, password: 123 (được mã hóa BCrypt)
                User mockUser = new User("admin", passwordEncoder.encode("123"), "ADMIN");
                userRepository.save(mockUser);
                System.out.println(">>> ĐÃ KHỞI TẠO TÀI KHOẢN MẪU THÀNH CÔNG: username: admin | password: 123");
            }
        };
    }
}

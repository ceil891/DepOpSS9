package com.explam.ss15.service;

import com.explam.ss15.dto.request.LoginRequest;
import com.explam.ss15.dto.request.RegisterRequest;
import com.explam.ss15.dto.response.AuthResponse;
import com.explam.ss15.entity.User;
import com.explam.ss15.repository.UserRepository;
import com.explam.ss15.security.JwtTokenProvider;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;

    public AuthService(UserRepository userRepository, PasswordEncoder passwordEncoder, JwtTokenProvider tokenProvider) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.tokenProvider = tokenProvider;
    }

    public String register(RegisterRequest request) {
        if (userRepository.existsByEmail(request.getEmail())) {
            throw new RuntimeException("Email đã được sử dụng rồi bạn ơi!");
        }

        User user = new User();
        user.setEmail(request.getEmail());
        user.setPassword(passwordEncoder.encode(request.getPassword()));
        user.setPhone(request.getPhone());
        user.setRole("ROLE_USER");

        userRepository.save(user);
        return "Đăng ký tài khoản thành công!";
    }

    public AuthResponse login(LoginRequest request) {
        User user = userRepository.findByEmail(request.getEmail())
                .orElseThrow(() -> new RuntimeException("Sai Email hoặc mật khẩu nhé!"));

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new RuntimeException("Sai Email hoặc mật khẩu nhé!");
        }

        // Tạo cặp token trả về cho client
        String accessToken = tokenProvider.generateAccessToken(user.getEmail(), user.getRole());
        String refreshToken = tokenProvider.generateRefreshToken(user.getEmail());

        return new AuthResponse(accessToken, refreshToken);
    }
}
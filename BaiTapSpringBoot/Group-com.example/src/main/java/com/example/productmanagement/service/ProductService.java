package com.example.productmanagement.service;

import com.example.productmanagement.model.Product;
import org.springframework.stereotype.Service;
import java.util.ArrayList;
import java.util.List;

@Service
public class ProductService {
    private List<Product> products = new ArrayList<>();

    public ProductService() {
        products.add(new Product(1, "iPhone 15", 1000));
        products.add(new Product(2, "Samsung S24", 900));
        products.add(new Product(3, "Macbook M3", 1500));
    }

    public List<Product> getAllProducts() {
        return products;
    }
}
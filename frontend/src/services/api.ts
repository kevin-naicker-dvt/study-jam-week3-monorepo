import axios from 'axios';

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000/api';

const api = axios.create({
  baseURL: API_URL,
  headers: { 'Content-Type': 'application/json' },
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('access_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export interface RegisterPayload {
  name: string;
  surname: string;
  email: string;
  password: string;
}

export interface LoginPayload {
  email: string;
  password: string;
}

export interface AuthResponse {
  message: string;
  access_token: string;
  user: {
    id: number;
    name: string;
    surname: string;
    email: string;
  };
}

export const authApi = {
  register: (data: RegisterPayload) =>
    api.post<{ id: number; name: string; surname: string; email: string }>(
      '/auth/register',
      data,
    ),
  login: (data: LoginPayload) => api.post<AuthResponse>('/auth/login', data),
};

export default api;

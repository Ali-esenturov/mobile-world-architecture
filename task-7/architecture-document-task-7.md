# MongoDB Architecture Document

## Общая цель
Документ описывает структуру коллекций MongoDB, выбранные shard keys, индексы и основные запросы с учётом:
- шардированного кластера (2 шарда)
- write‑heavy нагрузки
- минимизации scatter‑gather
- простоты поддержки и масштабирования

---

## 1. Orders Collection

### Назначение
Хранение заказов пользователей, их статусов и истории.

### Основные операции
- Создание заказа
- Получение истории заказов пользователя
- Проверка статуса заказа

### Структура документа
```js
{
  _id: ObjectId,
  user_id: ObjectId,
  order_date: Date,
  items_list: [
    {
      product_id: ObjectId,
      quantity: Number,
      price: Number
    }
  ],
  order_status: "created" | "paid" | "shipped" | "cancelled",
  total_sum: Number,
  geolocation: String
}
```

### Shard Key
```js
{ user_id: "hashed" }
```

### Обоснование
- Большинство запросов завязаны на пользователя
- Равномерное распределение write‑нагрузки
- История заказов всегда в одном шарде

### Индексы
```js
{ user_id: 1, order_date: -1 }
{ user_id: 1, order_status: 1 }
```

### Типовые запросы
```js
// Создание заказа
insertOne(order)

// История заказов пользователя
find({ user_id }).sort({ order_date: -1 })

// Проверка статуса
findOne({ _id })
```

---

## 2. Products Collection

### Назначение
Каталог товаров и управление остатками.

### Основные операции
- Обновление остатков при покупке
- Поиск товаров по категории и цене
- Чтение карточки товара

### Структура документа
```js
{
  _id: ObjectId,
  name: String,
  category: String,
  price: Number,
  remains_list: [
    {
      geolocation: String,
      amount: Number
    }
  ],
  attributes: [
    {
      size: String,
      color: String
    }
  ]
}
```

### Shard Key
```js
{ _id: "hashed" }
```

### Обоснование
- Частые точечные update по product_id
- Равномерное распределение данных
- Поиск каталога допускает scatter‑gather

### Индексы
```js
{ category: 1, price: 1 }
{ "remains_list.geolocation": 1 }
```

### Типовые запросы
```js
// Карточка товара
findOne({ _id })

// Каталог
find({ category, price: { $gte, $lte } })

// Списание остатков
updateOne(
  { _id, "remains_list.geolocation": geo },
  { $inc: { "remains_list.$.amount": -qty } }
)
```

---

## 3. Carts Collection

### Назначение
Работа с корзинами пользователей и гостей.

### Основные операции
- Создание корзины
- Получение активной корзины
- Добавление / удаление товаров
- Слияние гостевой корзины с пользовательской
- Пометка корзины как заказанной

### Ключевая идея
Используется **единый shard key owner_id**, который может быть:
- user_id для авторизованных
- session_id для гостей

---

### Структура документа
```js
{
  _id: ObjectId,
  owner_id: String | ObjectId,
  owner_type: "user" | "session",
  user_id: ObjectId | null,
  session_id: String | null,
  status: "active" | "ordered" | "abandoned",
  items_list: [
    {
      product_id: ObjectId,
      quantity: Number,
      price: Number
    }
  ],
  created_at: Date,
  updated_at: Date,
  expires_at: Date
}
```

### Shard Key
```js
{ owner_id: "hashed" }
```

### Обоснование
- Все операции всегда выполняются по владельцу корзины
- Один shard для одной активной корзины
- Упрощает routing и масштабирование

### Индексы
```js
{ owner_id: 1, status: 1 }
{ user_id: 1, status: 1 }
{ session_id: 1, status: 1 }
{ expires_at: 1 }
```

### Типовые запросы
```js
// Получение активной корзины пользователя
findOne({ user_id, status: "active" })

// Получение корзины гостя
findOne({ session_id, status: "active" })

// Добавление товара
updateOne(
  { owner_id, status: "active" },
  { $set: { items_list }, $currentDate: { updated_at: true } }
)

// Слияние корзин
find({ session_id, status: "active" })
find({ user_id, status: "active" })
```

---

## Общие архитектурные принципы

- Shard key всегда присутствует в write‑операциях
- Нет cross‑shard транзакций в hot‑path
- Денормализация предпочтительнее $lookup
- TTL используется для очистки временных данных

---

## Итоговая таблица

| Collection | Shard Key | Основной доступ |
|---------|----------|---------------|
| Orders | user_id (hashed) | по пользователю |
| Products | _id (hashed) | по product_id |
| Carts | owner_id (hashed) | по владельцу |

---
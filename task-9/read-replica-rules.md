# MongoDB Read from Primary/Repilcas

## Правила для коллекций

| Коллекция | Read from replica | Допустимая задержка | Обоснование |
|-----------|-------------------|---------------------|-------------|
| Products         | yes        | <=3 сек  | read-heavy, eventual consistency |
| Orders (history) | yes        | <=10 сек | read-only данные                 |
| Orders (status)  | no         | 0        | бизнес-инварианты                |
| Carts            | no         | 0        | write-heavy, критично            |


### Products
Каталог и карточка товара — read-heavy
Остатки обновляются часто, но:
- краткая рассинхронизация не критична
- реальная проверка остатков делается на primary при создании заказа

### Orders
Primary — для статуса и недавних заказов
Secondary — для истории заказов
- Статус заказа участвует в бизнес-логике (оплата, доставка)
- История — read-only, допускает eventual consistency

### Carts
Только primary
Корзина — write-heavy
- Любая задержка - это потеря товаров, race conditions
- Слияние корзин требует актуального состояния

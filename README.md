# issue-gtd-agent

ИИ-автоматизация GTD-системы поверх GitHub Issues.

Если вы ведёте свой GTD (или «9 списков») в GitHub — этот проект берёт на себя рутину: разбирает входящие, формулирует задачи, раскладывает их по спискам и отвечает вам в комментариях к Issue.

## Как это работает

Каждая задача — это GitHub Issue. Когда вы создаёте Issue или пишете комментарий, срабатывает GitHub Actions workflow. Он читает, в какой колонке Kanban-доски находится задача, и запускает нужный ИИ-промпт из папки `stages/`. Агент отвечает комментарием к тому же Issue.

**9 GTD-списков** реализованы как колонки GitHub Project (Kanban):

| Колонка | Назначение |
|---|---|
| Inbox | Всё подряд — идеи, задачи, заметки |
| Next Actions | Конкретные одношаговые дела на сегодня |
| Projects | Многошаговые проекты |
| Calendar | Дела с привязкой к дате |
| Waiting For | Жду ответа / результата от кого-то |
| Someday / Maybe | Когда-нибудь, может быть |
| Reference | Справочная информация |
| Trash | Корзина |
| Done | Выполнено |

## Настройка

### 1. Создайте свой репозиторий и скопируйте код

```bash
git clone https://github.com/your-org/issue-gtd-agent.git my-gtd
cd my-gtd

git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO.git

git push -u origin main
```

### 2. Добавьте секреты

Перейдите в **Settings → Secrets and variables → Actions** вашего репозитория и создайте два секрета:

| Name | Value |
|---|---|
| `PERSONAL_ACCESS_TOKEN` | ваш [GitHub Personal Access Token](https://github.com/settings/tokens) со скоупами `repo`, `project`, `workflow` |
| `CURSOR_API_KEY` | ваш ключ Cursor API |

### 4. Запустите workflow `Init`

Перейдите в **Actions → Init → Run workflow**.

Workflow создаст GitHub Project с Kanban-доской и 9 GTD-колонками, привяжет его к вашему репозиторию и запишет идентификаторы в `settings.yml`.

После этого система готова к работе.

## Использование

- Создайте Issue — агент обработает его как **Inbox**: уточнит формулировку и добавит описание.
- Переместите Issue в нужную колонку на Kanban-доске — агент применит соответствующую логику GTD.
- Напишите комментарий к любому Issue — агент ответит.

## Персонализация

- `USER_CONTEXT.md` — расскажите агенту о себе: ваши цели, контекст, привычки. Это его долгосрочная память о вас.
- `COMMON.md` — базовые инструкции и характер агента.
- `stages/*.md` — промпты для каждого GTD-списка. Редактируйте под свои нужды.
- `settings.yml` — модель и привязки к проекту/колонкам.

## Структура проекта

```
.
├── .github/
│   ├── actions/          # Переиспользуемые шаги (commit-and-push, cursor-agent-run и др.)
│   ├── scripts/          # Bash/Python скрипты инициализации
│   └── workflows/
│       ├── init.yml          # Однократная настройка проекта
│       ├── executors.yml     # Основной workflow — реагирует на Issues и комментарии
│       └── issues-backup.yml # Бэкап Issues
├── stages/               # GTD-промпты для каждой колонки
├── COMMON.md             # Системный промпт агента
├── USER_CONTEXT.md       # Контекст о пользователе
└── settings.yml          # Конфигурация: модель, repo id, project id, колонки
```

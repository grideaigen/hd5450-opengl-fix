# Radeon HD 5450 на Windows 11: как вернуть аппаратный OpenGL 4.5 (диалог «Error 126» и fallback на GDI Generic)

## Введение

Windows 11 официально не поддерживает драйверы Radeon HD 5000 серии — их развитие остановилось
на версии 15.201.1151 (2015 год). На практике драйвер ставится и работает, но при попытке
создать OpenGL-контекст приложение падает с системным диалогом:

```
The application was unable to start (0xc000007b / «Error 126»)
или wglCreateContext возвращает NULL
```

либо контекст создаётся, но GL отвечает `GDI Generic 1.1.0` — то есть рендер уходит
в софтварную эмуляцию без аппаратного ускорения.

Эта статья описывает, как найти причину (она не в драйвере и не в карте) и починить стек
без переустановки системы. Итог: `ATI Technologies Inc. / AMD Radeon HD 5450 / 4.5.13399
Compatibility Profile Context` — максимум для легаси-стека, аппаратный контекст.

Кейс проверен на конфигурации: Windows 11 (x64), Radeon HD 5450 (Terascale 2) +
Tesla V100 в роли вычислительной карты.

## Как устроен выбор ICD в Windows (коротко)

При создании контекста `opengl32.dll` ищет клиентский драйвер (ICD) в трёх местах реестра:

1. `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-...}\000N`
   — параметры `OpenGLDriverName` (64-бит) и `OpenGLDriverNameWoW` (32-бит);
2. `HKLM\SYSTEM\CurrentControlSet\Control\Video\{GUID}\000N` — то же самое, дублируется
   драйвером;
3. `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers` — регистрация
   для утилит (GPU-Z и др.).

Дальше opengl32 грузит ICD, вызывает его экспорт `DrvValidateVersion(OpenGLVersion)`
и если ответ «не моё» — **тихо** скатывается в GDI Generic, без диалогов и кодов ошибок.
Ядро кэширует ICD до перезапуска видеодрайвера: правки реестра не действуют, пока
не сделать `pnputil /restart-device <InstanceId>` или перезагрузку.

## Диагностика

1. **Найти реестровые записи** обоих адаптеров: перебрать
   `Control\Class\{4d36e968...}\0000..0003` и `Control\Video\{GUID}\000N`,
   сравнить `DriverDesc`, `OpenGLDriverName`, `OpenGLVersion`.

2. **Минимальный тест контекста** (PowerShell + Add-Type с P/Invoke:
   GetDC → ChoosePixelFormat → SetPixelFormat → wglCreateContext → wglMakeCurrent →
   glGetString). Логировать каждый шаг и `GetLastWin32Error`. Пример структуры теста:

```powershell
# ключевые вызовы (упрощённо)
$ctx = [U6.G5]::wglCreateContext($dc)   # NULL -> логируем код ошибки
$ok  = [U6.G5]::wglMakeCurrent($dc, $ctx)
# glGetString(GL_VENDOR/GL_RENDERER/GL_VERSION) -> 0x1F00, 0x1F01, 0x1F02
```

3. **Дампить модули при живом контексте**: если в памяти есть `atio6axx.dll` (AMD ICD),
   а GL всё равно `GDI Generic` — ICD грузится, но отклоняется при выборе пиксельного
   формата. Ловится простым перечислением `Process.Modules` внутри того же процесса,
   без таймингов из второго окна.

4. **Проверить, какой формат выбран**: `DescribePixelFormat` и посмотреть флаги
   `PFD_GENERIC_FORMAT` (0x40, софтвар) и `PFD_GENERIC_ACCELERATED` (0x1000).
   Если ручной `PIXELFORMATDESCRIPTOR` (`dwFlags = 0x25`: support GDI+OpenGL,
   doublebuffer; 24-бит цвет, 24-бит глубина) выбирает формат 7 — не generic —
   и контекст становится аппаратным, значит система на дефолтных запросах отдаёт
   формат, который легаси-ICD не обслуживает.

5. **Проверить версию ICD против кернел-драйвера** — они должны быть из одного пакета:

```powershell
(Get-Item C:\Windows\System32\atio6axx.dll).VersionInfo.FileVersion
# 6.14.10.13399 — совпадает с пакетом c0296217.inf / oem2.inf (15.201.1151.1008)
```

6. **Прямо спросить ICD о валидации** (безопасно: только LoadLibrary + GetProcAddress):

```powershell
# вызов DrvValidateVersion из atio6axx.dll перебором значений
# результат: значение 1 -> TRUE, всё остальное -> false
```

7. **Исключить вторую видеокарту** (если есть): временно отключить её через
   `pnputil /disable-device "<InstanceId>"` и повторить тест. В этом кейсе Tesla
   ни при чём — generic сохранялся и без неё.

## Суть решения

Всё лечится реестром, без файлов «руками»:

1. В класс-ключах карты (`Control\Class\{4d36e968...}\0000`, `0003`) значения:

```
OpenGLDriverName     = atio6axx.dll      (64-бит ICD)
OpenGLDriverNameWoW  = atioglxx.dll      (32-бит ICD)
```

Прямой ICD вместо цепочки стабов (`atig6pxx` и подобных) — стаб-заглушки в этом
стеке часто битые и ведут себя непредсказуемо.

2. В `Control\Video\{GUID}\000N` — те же значения, плюс `OpenGLVersion = 1`
   (именно эту цифру просит `DrvValidateVersion` легаси-ICD 15.201.1151; проверить
   можно пробом экспорта, как выше).

3. Регистрации для утилит:

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers
    atio6axx = atio6axx.dll
HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\OpenGLDrivers
    atioglxx = atioglxx.dll
```

4. **Обязательно** перезапустить видеодрайвер, иначе кэш ядра не обновится:

```powershell
$adapt = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'Radeon|AMD' }
pnputil /restart-device $adapt.InstanceId
```

После этого тест показывает:

```
GL: ATI Technologies Inc.
GL: AMD Radeon HD 5450
GL: 4.5.13399 Compatibility Profile Context 0
```

## Ограничения и что не делать

- Современный пакет `amdogl.inf` (SoftwareComponent, 2026) в DriverStore **не совместим**
  с кернел-драйвером 2015 года — его ICD не подхватится. Не пытаться смешивать.
- Не «чинить» стабильные заглушки в System32/SysWOW64 подменой файлов: рабочий вариант —
  прямой ICD, а заглушки оставить как есть.
- Галочка OpenGL в GPU-Z — про **активного провайдера** API, а не про возможности карты.
  При переключении просмотра между картами она «исчезает» — это норма.
- После крупных обновлений Windows (сборки 24H2/25H2 и далее) проверку стоит повторить:
  обновление может пересобрать реестр и вернуть заглушки. Хранить фикс-скрипт рядом
  с пакетом драйвера.

## Страховочный комплект

Рекомендую сразу сохранить в папку:

- полный пакет драйвера из DriverStore:
  `C:\Windows\System32\DriverStore\FileRepository\c0296217.inf_amd64_*` (вся папка);
- скрипт фикса (реестр + перезапуск адаптера с автоопределением через `Get-PnpDevice`);
- скрипт теста контекста с логированием каждого шага и `GetLastWin32Error`.

Установка на чистой системе: `pnputil /add-driver c0296217.inf /install`, затем фикс,
затем тест. Всё переживает перезагрузку.

## Вывод

Легаси-карта на современной Windows — не приговор. Диалог ошибки 126 и «GDI Generic»
в этом кейсе были следствием трёх независимых вещей: битой цепочки стабов в реестре,
неверного выбора пиксельного формата и несброшенного кэша ICD. Ни карта, ни драйвер
не требовали замены — только корректной записи в реестр и честного перезапуска
видеодрайвера. Аппаратный OpenGL 4.5 Compatibility Profile на HD 5450 под Windows 11 —
рабочая конфигурация.

---

*Автор не несёт ответственности за изменения реестра: делайте экспорт веток перед правками.
Все команды выполнялись с правами администратора.*

-- =============================================
-- АУРУХАНА НАУҚАСТАРДЫ ТІРКЕУ ЖҮЙЕСІ
-- =============================================

-- 1. ЕСКІ КЕСТЕЛЕРДІ ТАЗАЛАУ
DROP TABLE IF EXISTS Тағайындалған_дәрілер CASCADE;
DROP TABLE IF EXISTS Науқас_диагнозы CASCADE;
DROP TABLE IF EXISTS Тіркеу CASCADE;
DROP TABLE IF EXISTS Пациент CASCADE;
DROP TABLE IF EXISTS Дәрігер CASCADE;
DROP TABLE IF EXISTS Диагноз_анықтама CASCADE;
DROP TABLE IF EXISTS Дәрі_анықтама CASCADE;
DROP TABLE IF EXISTS тіркеу_лог CASCADE;
DROP TABLE IF EXISTS жүйе_лог CASCADE;
DROP VIEW IF EXISTS науқас_соңғы_тіркеу CASCADE;

-- 2. НОРМАЛИЗАЦИЯ (3NF + BCNF) – КЕСТЕЛЕРДІ ҚҰРУ
CREATE TABLE Пациент (
    пациент_ид SERIAL PRIMARY KEY,
    аты VARCHAR(100) NOT NULL,
    телефон VARCHAR(20),
    туған_күні DATE
);

CREATE TABLE Дәрігер (
    дәрігер_ид SERIAL PRIMARY KEY,
    аты VARCHAR(100) NOT NULL,
    мамандық VARCHAR(100),
    бөлімше VARCHAR(100)
);

CREATE TABLE Тіркеу (
    тіркеу_ид SERIAL PRIMARY KEY,
    пациент_ид INTEGER REFERENCES Пациент(пациент_ид) ON DELETE CASCADE,
    дәрігер_ид INTEGER REFERENCES Дәрігер(дәрігер_ид),
    тіркеу_күні DATE NOT NULL,
    бару_мақсаты TEXT
);

CREATE TABLE Диагноз_анықтама (
    диагноз_коды VARCHAR(10) PRIMARY KEY,
    атауы VARCHAR(200) NOT NULL,
    санаты VARCHAR(100)
);

CREATE TABLE Науқас_диагнозы (
    тіркеу_ид INTEGER REFERENCES Тіркеу(тіркеу_ид) ON DELETE CASCADE,
    диагноз_коды VARCHAR(10) REFERENCES Диагноз_анықтама(диагноз_коды),
    PRIMARY KEY (тіркеу_ид, диагноз_коды)
);

CREATE TABLE Дәрі_анықтама (
    дәрі_коды VARCHAR(10) PRIMARY KEY,
    атауы VARCHAR(100) NOT NULL,
    өлшем_бірлігі VARCHAR(20)
);

CREATE TABLE Тағайындалған_дәрілер (
    тіркеу_ид INTEGER REFERENCES Тіркеу(тіркеу_ид) ON DELETE CASCADE,
    дәрі_коды VARCHAR(10) REFERENCES Дәрі_анықтама(дәрі_коды),
    дозасы VARCHAR(50),
    PRIMARY KEY (тіркеу_ид, дәрі_коды)
);

-- 3. ПРОЦЕДУРАЛАР (4 дана)
CREATE OR REPLACE PROCEDURE пациент_қосу(
    p_аты VARCHAR,
    p_телефон VARCHAR,
    p_туған_күні DATE DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO Пациент (аты, телефон, туған_күні) 
    VALUES (p_аты, p_телефон, p_туған_күні);
    RAISE NOTICE 'Пациент % қосылды', p_аты;
END;
$$;

CREATE OR REPLACE PROCEDURE тіркеу_жасау(
    p_пациент_ид INT,
    p_дәрігер_ид INT,
    p_тіркеу_күні DATE,
    p_мақсаты TEXT DEFAULT 'Қаралу'
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO Тіркеу (пациент_ид, дәрігер_ид, тіркеу_күні, бару_мақсаты)
    VALUES (p_пациент_ид, p_дәрігер_ид, p_тіркеу_күні, p_мақсаты);
    RAISE NOTICE 'Тіркеу №% жасалды', (SELECT lastval());
END;
$$;

CREATE OR REPLACE PROCEDURE диагноз_қосу(
    p_тіркеу_ид INT,
    p_диагноз_коды VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO Науқас_диагнозы (тіркеу_ид, диагноз_коды) 
    VALUES (p_тіркеу_ид, p_диагноз_коды)
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE дәрі_тағайындау(
    p_тіркеу_ид INT,
    p_дәрі_коды VARCHAR,
    p_дозасы VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO Тағайындалған_дәрілер (тіркеу_ид, дәрі_коды, дозасы)
    VALUES (p_тіркеу_ид, p_дәрі_коды, p_дозасы);
END;
$$;

-- 4. ҚОЛДАНУШЫ ФУНКЦИЯЛАРЫ (4 дана)
CREATE OR REPLACE FUNCTION пациент_тіркеу_саны(p_пациент_ид INT)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE саны INT;
BEGIN
    SELECT COUNT(*) INTO саны FROM Тіркеу WHERE пациент_ид = p_пациент_ид;
    RETURN саны;
END;
$$;

CREATE OR REPLACE FUNCTION дәрігер_бүгінгі_жүктеме(p_дәрігер_ид INT)
RETURNS INT
LANGUAGE sql AS $$
    SELECT COUNT(*) FROM Тіркеу 
    WHERE дәрігер_ид = p_дәрігер_ид AND тіркеу_күні = CURRENT_DATE;
$$;

CREATE OR REPLACE FUNCTION ең_көп_диагноз(p_бастау DATE, p_аяқ DATE)
RETURNS TABLE(диагноз_коды VARCHAR, атауы VARCHAR, саны BIGINT)
LANGUAGE sql AS $$
    SELECT nd.диагноз_коды, да.атауы, COUNT(*) AS саны
    FROM Науқас_диагнозы nd
    JOIN Тіркеу t ON nd.тіркеу_ид = t.тіркеу_ид
    JOIN Диагноз_анықтама да ON nd.диагноз_коды = да.диагноз_коды
    WHERE t.тіркеу_күні BETWEEN p_бастау AND p_аяқ
    GROUP BY nd.диагноз_коды, да.атауы
    ORDER BY саны DESC
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION науқас_дәрілері(p_пациент_ид INT)
RETURNS TABLE(дәрі_атауы VARCHAR, дозасы VARCHAR, тіркеу_күні DATE)
LANGUAGE sql AS $$
    SELECT да.атауы, тд.дозасы, t.тіркеу_күні
    FROM Тағайындалған_дәрілер тд
    JOIN Дәрі_анықтама да ON тд.дәрі_коды = да.дәрі_коды
    JOIN Тіркеу t ON тд.тіркеу_ид = t.тіркеу_ид
    WHERE t.пациент_ид = p_пациент_ид
    ORDER BY t.тіркеу_күні DESC;
$$;

-- 5. ТРИГГЕРЛЕР
-- 5.1 Лог-триггер (жол деңгейінде)
CREATE TABLE тіркеу_лог (
    лог_ид SERIAL PRIMARY KEY,
    тіркеу_ид INT,
    әрекет VARCHAR(10),
    ескі_пациент_ид INT,
    жаңа_пациент_ид INT,
    өзгерту_уақыты TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    қолданушы VARCHAR(50) DEFAULT current_user
);

CREATE OR REPLACE FUNCTION тіркеу_лог_функц()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO тіркеу_лог (тіркеу_ид, әрекет, ескі_пациент_ид)
        VALUES (OLD.тіркеу_ид, 'DELETE', OLD.пациент_ид);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO тіркеу_лог (тіркеу_ид, әрекет, ескі_пациент_ид, жаңа_пациент_ид)
        VALUES (NEW.тіркеу_ид, 'UPDATE', OLD.пациент_ид, NEW.пациент_ид);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO тіркеу_лог (тіркеу_ид, әрекет, жаңа_пациент_ид)
        VALUES (NEW.тіркеу_ид, 'INSERT', NEW.пациент_ид);
        RETURN NEW;
    END IF;
END;
$$;

CREATE TRIGGER тіркеу_лог_триггер
AFTER INSERT OR UPDATE OR DELETE ON Тіркеу
FOR EACH ROW EXECUTE FUNCTION тіркеу_лог_функц();

-- 5.2 Оператор деңгейіндегі триггер
CREATE OR REPLACE FUNCTION көп_өшіруге_тыйым()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT COUNT(*) FROM Тіркеу) > 20 THEN
        RAISE EXCEPTION 'Қауіпсіздік: 20-дан артық жазбаны өшіруге рұқсат жоқ';
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER көп_тіркеу_өшіру_алды
BEFORE DELETE ON Тіркеу
FOR EACH STATEMENT
EXECUTE FUNCTION көп_өшіруге_тыйым();

-- 5.3 Жол деңгейіндегі тексеру триггері (дәрі коды)
CREATE OR REPLACE FUNCTION дәрі_тексеру()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Дәрі_анықтама WHERE дәрі_коды = NEW.дәрі_коды) THEN
        RAISE EXCEPTION 'Мұндай дәрі коды жоқ: %', NEW.дәрі_коды;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER дәрі_тексеру_триггер
BEFORE INSERT OR UPDATE ON Тағайындалған_дәрілер
FOR EACH ROW EXECUTE FUNCTION дәрі_тексеру();

-- 5.4 INSTEAD OF триггер (көрініс арқылы INSERT)
CREATE VIEW науқас_соңғы_тіркеу AS
SELECT p.пациент_ид, p.аты, MAX(t.тіркеу_күні) соңғы_күн
FROM Пациент p
LEFT JOIN Тіркеу t ON p.пациент_ид = t.пациент_ид
GROUP BY p.пациент_ид, p.аты;

CREATE OR REPLACE FUNCTION көрініске_тіркеу_қосу()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO Тіркеу (пациент_ид, тіркеу_күні, бару_мақсаты) 
    VALUES (NEW.пациент_ид, CURRENT_DATE, 'Автоматты тіркеу');
    RETURN NEW;
END;
$$;

CREATE TRIGGER көрініс_триггер
INSTEAD OF INSERT ON науқас_соңғы_тіркеу
FOR EACH ROW EXECUTE FUNCTION көрініске_тіркеу_қосу();
.
-- 6. ТЕСТ ДЕРЕКТЕРІ
INSERT INTO Пациент (аты, телефон) VALUES ('Асан', '87001112233'), ('Марат', '87022223344');
INSERT INTO Дәрігер (аты, мамандық, бөлімше) VALUES ('Ермеков', 'Кардиолог', 'Кардио'), ('Сагиндыкова', 'Терапевт', 'Терапия');
INSERT INTO Диагноз_анықтама (диагноз_коды, атауы) VALUES ('I10', 'Гипертония'), ('J11', 'Тұмау');
INSERT INTO Дәрі_анықтама (дәрі_коды, атауы) VALUES ('ASP01', 'Аспирин'), ('PAR01', 'Парацетамол');

-- 7. ПРОЦЕДУРАЛАРДЫ ТЕСТІЛЕУ
CALL пациент_қосу('Әлия', '87025556677', '1990-05-10');
CALL тіркеу_жасау(1, 1, '2025-04-27', 'Жүрек айну');
CALL диагноз_қосу(1, 'I10');
CALL дәрі_тағайындау(1, 'ASP01', '100 мг');

-- 8. ФУНКЦИЯЛАРДЫ ТЕСТІЛЕУ
SELECT пациент_тіркеу_саны(1) AS тіркеу_саны;
SELECT дәрігер_бүгінгі_жүктеме(1) AS бүгінгі_жүктеме;
SELECT * FROM ең_көп_диагноз('2025-04-01', '2025-04-30');
SELECT * FROM науқас_дәрілері(1);

-- 9. ТРАНЗАКЦИЯЛАР (ACID)
-- Транзакция 1: өзгерістерді сақтау (COMMIT)
BEGIN;
    CALL тіркеу_жасау(2, 2, '2025-04-28', 'Қызу');
    CALL диагноз_қосу(2, 'J11');
    CALL дәрі_тағайындау(2, 'PAR01', '500 мг');
COMMIT;

-- Транзакция 2: SAVEPOINT және ROLLBACK TO
BEGIN;
    CALL тіркеу_жасау(1, 1, '2025-04-29', 'Қайта тексеру');
    SAVEPOINT бірінші_нүкте;
    CALL дәрі_тағайындау(3, 'ASP01', '150 мг'); -- тіркеу_ид=3
    ROLLBACK TO бірінші_нүкте;
    -- дәрі тағайындау өшеді, Тіркеу қалады
COMMIT;

-- Алдыңғы бұзылған транзакцияны тоқтату (егер бар болса)
ROLLBACK;

-- Транзакция №3 (сәтсіз болса ROLLBACK)
DO $$
BEGIN
    CALL тіркеу_жасау(2, 2, '2025-04-30', 'Қате диагноз');
    CALL диагноз_қосу(4, 'Жоқ_код');
    INSERT INTO Науқас_диагнозы (тіркеу_ид, диагноз_коды) VALUES (4, 'Z99');
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE NOTICE 'Қате болды, барлығы кері қайтарылды. %', SQLERRM;
END;
$$; 

ROLLBACK;

-- 10. БАРЛЫҚ НӘТИЖЕЛЕРДІ ҚОРЫТЫНДЫЛАУ
SELECT * FROM Тіркеу;
SELECT * FROM тіркеу_лог;
SELECT * FROM науқас_соңғы_тіркеу;
INSERT INTO науқас_соңғы_тіркеу (пациент_ид, аты) VALUES (1, 'Асан');
SELECT * FROM науқас_соңғы_тіркеу; 


DROP TABLE IF EXISTS Тіркеу, Пациент, тіркеу_лог CASCADE;
CREATE TABLE Пациент(ид INT PRIMARY KEY, аты TEXT);
CREATE TABLE Тіркеу(ид SERIAL PRIMARY KEY, п_ид INT REFERENCES Пациент, күні DATE);
CREATE TABLE тіркеу_лог(лог TEXT);

CREATE OR REPLACE PROCEDURE т_жасау(p INT, к DATE) LANGUAGE plpgsql AS $$ BEGIN INSERT INTO Тіркеу(п_ид,күні) VALUES(p,к); END; $$;
CREATE OR REPLACE FUNCTION т_саны(p INT) RETURNS INT LANGUAGE sql AS $$ SELECT COUNT(*) FROM Тіркеу WHERE п_ид=p; $$;
CREATE OR REPLACE FUNCTION лог_фн() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN INSERT INTO тіркеу_лог VALUES(TG_OP); RETURN NEW; END; $$;
CREATE TRIGGER лог_tr AFTER INSERT ON Тіркеу FOR EACH ROW EXECUTE FUNCTION лог_фн();

INSERT INTO Пациент VALUES(1,'Асан');

BEGIN; CALL т_жасау(1,'2025-04-27'); SAVEPOINT s; CALL т_жасау(1,'2025-04-28'); ROLLBACK TO s; COMMIT;
DO $$ BEGIN CALL т_жасау(99,'2025-04-29'); EXCEPTION WHEN OTHERS THEN ROLLBACK; END; $$;

SELECT * FROM Тіркеу; SELECT * FROM тіркеу_лог; SELECT т_саны(1) AS саны;


ROLLBACK;
DROP TABLE IF EXISTS Т_лог, Т_дәр, Т_диаг, Т, P, D, C, M CASCADE;
CREATE TABLE P(p INT PRIMARY KEY, аты TEXT, тел TEXT);
CREATE TABLE D(d INT PRIMARY KEY, аты TEXT, мам TEXT);
CREATE TABLE T(t SERIAL PRIMARY KEY, p INT REFERENCES P, d INT REFERENCES D, k DATE);
CREATE TABLE C(c TEXT PRIMARY KEY, аты TEXT);
CREATE TABLE Т_диаг(t INT REFERENCES T, c TEXT REFERENCES C);
CREATE TABLE M(m TEXT PRIMARY KEY, аты TEXT, бірлік TEXT);
CREATE TABLE Т_дәр(t INT REFERENCES T, m TEXT REFERENCES M, доза TEXT);
CREATE TABLE Т_лог(t INT, оп TEXT, у TIMESTAMP DEFAULT NOW());

CREATE OR REPLACE FUNCTION лф() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN INSERT INTO Т_лог VALUES(NEW.t,TG_OP); RETURN NEW; END; $$;
CREATE TRIGGER лт AFTER INSERT ON T FOR EACH ROW EXECUTE FUNCTION лф();
CREATE OR REPLACE PROCEDURE тж(p INT, d INT, k DATE) LANGUAGE plpgsql AS $$ BEGIN INSERT INTO T(p,d,k) VALUES(p,d,k); END; $$;
CREATE OR REPLACE FUNCTION тс(p INT) RETURNS INT LANGUAGE sql AS $$ SELECT COUNT(*) FROM T WHERE p=$1; $$;

INSERT INTO P VALUES(1,'Асан','870111'),(2,'Марат','870222'),(3,'Әлия','870333');
INSERT INTO D VALUES(1,'Ермеков','Кардиолог'),(2,'Сагиндыкова','Терапевт');
INSERT INTO C VALUES('I10','Гипертония'),('J11','Тұмау'),('E11','Қант диабеті');
INSERT INTO M VALUES('A01','Аспирин','мг'),('P01','Парацетамол','мг'),('M01','Метформин','мг');

BEGIN; CALL тж(1,1,'2025-04-27'); CALL тж(2,2,'2025-04-28'); COMMIT;
BEGIN; CALL тж(1,1,'2025-04-29'); SAVEPOINT s; CALL тж(3,2,'2025-04-30'); ROLLBACK TO s; COMMIT;
DO $$ BEGIN CALL тж(99,99,'2025-05-01'); EXCEPTION WHEN OTHERS THEN ROLLBACK; END; $$;

INSERT INTO Т_диаг VALUES(1,'I10'),(2,'J11'),(3,'E11');
INSERT INTO Т_дәр VALUES(1,'A01','100'),(2,'P01','500'),(3,'M01','850');

-- Толық нәтиже барлық байланыстарымен
SELECT t.t, p.аты AS пациент, d.аты AS дәрігер, t.k AS күні,
       (SELECT string_agg(c.аты, ', ') FROM Т_диаг td JOIN C c ON td.c=c.c WHERE td.t=t.t) AS диагноздар,
       (SELECT string_agg(m.аты||' ('||td.доза||' '||m.бірлік||')', ', ') 
        FROM Т_дәр td JOIN M m ON td.m=m.m WHERE td.t=t.t) AS дәрілер
FROM T t JOIN P p ON t.p=p.p JOIN D d ON t.d=d.d ORDER BY t.t;
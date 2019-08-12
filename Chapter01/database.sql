CREATE DATABASE IF NOT EXISTS chapter01;

USE chapter01;

CREATE TABLE IF NOT EXISTS chapter01.people (
    name        VARCHAR(100),
    title       VARCHAR(10),
    description VARCHAR(100),
    PRIMARY KEY (name)
);

DELETE FROM chapter01.people;

INSERT INTO chapter01.people VALUES ('Gru', 'Felonius', 'Where are the minions?');
INSERT INTO chapter01.people VALUES ('Nefario', 'Dr.', 'Why ... why are you so old?');
INSERT INTO chapter01.people VALUES ('Agnes', '', 'Your unicorn is so fluffy!');
INSERT INTO chapter01.people VALUES ('Edith', '', "Don't touch anything!");
INSERT INTO chapter01.people VALUES ('Vector', '', 'Committing crimes with both direction and magnitude!');
INSERT INTO chapter01.people VALUES ('Dave', 'Minion', 'Ngaaahaaa! Patalaki patalaku Big Boss!!');

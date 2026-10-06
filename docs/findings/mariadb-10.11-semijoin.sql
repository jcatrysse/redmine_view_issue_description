-- MariaDB 10.11.14 (Ubuntu 24.04 package 10.11.14-MariaDB-0ubuntu0.24.04.1):
-- wrong result for the condition Redmine core builds in Issue.visible_condition
-- for a project-scoped issue list (IssueQuery with a project), for a member of a
-- public project whose role sees all issues ("(1=1)").
-- Found by test/e2e/description_lists.mjs: the user "scoped" got an empty issue
-- list on MariaDB, the same data on PostgreSQL 16 lists 8 issues.
-- Tables reduced to the columns the query uses, data from the e2e seed.
--   mariadb < docs/findings/mariadb-10.11-semijoin.sql
-- Expected 8 twice; MariaDB 10.11.14 answers 0, then 8 with semijoin=off.
DROP DATABASE IF EXISTS mdb_semijoin_repro;
CREATE DATABASE mdb_semijoin_repro;
USE mdb_semijoin_repro;
CREATE TABLE `issues` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `project_id` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `issues_project_id` (`project_id`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `issues` VALUES
(1,1),
(2,1),
(3,1),
(4,1),
(5,1),
(7,1),
(8,1),
(9,1),
(6,2);
CREATE TABLE `projects` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `projects` VALUES
(1),
(2);
CREATE TABLE `enabled_modules` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `project_id` int(11) DEFAULT NULL,
  `name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `enabled_modules_project_id` (`project_id`)
) ENGINE=InnoDB AUTO_INCREMENT=27 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `enabled_modules` VALUES
(1,1,'issue_tracking'),
(2,1,'time_tracking'),
(3,1,'news'),
(4,1,'documents'),
(5,1,'files'),
(6,1,'wiki'),
(7,1,'repository'),
(8,1,'boards'),
(9,1,'calendar'),
(10,1,'gantt'),
(11,1,'deals'),
(12,1,'contacts'),
(13,1,'contacts_helpdesk'),
(14,2,'issue_tracking'),
(15,2,'time_tracking'),
(16,2,'news'),
(17,2,'documents'),
(18,2,'files'),
(19,2,'wiki'),
(20,2,'repository'),
(21,2,'boards'),
(22,2,'calendar'),
(23,2,'gantt'),
(24,2,'deals'),
(25,2,'contacts'),
(26,2,'contacts_helpdesk');
CREATE TABLE `members` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL DEFAULT 0,
  `project_id` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_members_on_user_id_and_project_id` (`user_id`,`project_id`),
  KEY `index_members_on_user_id` (`user_id`),
  KEY `index_members_on_project_id` (`project_id`)
) ENGINE=InnoDB AUTO_INCREMENT=36 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `members` VALUES
(1,5,1),
(2,5,2),
(3,6,1),
(4,8,1),
(5,9,1),
(6,10,1),
(7,11,1),
(8,12,1),
(9,13,1),
(10,14,1),
(11,15,1),
(12,16,1),
(13,17,1),
(14,18,1),
(15,19,1),
(16,20,1),
(17,21,1),
(18,22,1),
(19,23,1),
(20,24,1),
(21,25,1),
(22,26,1),
(23,27,1),
(24,28,1),
(25,29,1),
(26,30,1),
(27,31,1),
(28,32,1),
(29,33,1),
(30,34,1),
(31,35,1),
(32,36,1),
(33,37,1),
(34,38,1),
(35,39,1);
SELECT count(*) AS expected_8 FROM issues INNER JOIN projects ON projects.id = issues.project_id
 WHERE ((((projects.id = 1) AND (EXISTS (SELECT 1 FROM enabled_modules em WHERE em.project_id = projects.id AND em.name='issue_tracking')))
   AND (((projects.id NOT IN (SELECT project_id FROM members WHERE user_id = 38))) OR (projects.id IN (1) AND (1=1)))));
SET SESSION optimizer_switch = 'semijoin=off';
SELECT count(*) AS expected_8_semijoin_off FROM issues INNER JOIN projects ON projects.id = issues.project_id
 WHERE ((((projects.id = 1) AND (EXISTS (SELECT 1 FROM enabled_modules em WHERE em.project_id = projects.id AND em.name='issue_tracking')))
   AND (((projects.id NOT IN (SELECT project_id FROM members WHERE user_id = 38))) OR (projects.id IN (1) AND (1=1)))));
DROP DATABASE mdb_semijoin_repro;

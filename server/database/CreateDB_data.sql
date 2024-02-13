-- Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
--
-- This file is part of AURORA, a system to store and manage science data.
--
-- AURORA is free software: you can redistribute it and/or modify it under 
-- the terms of the GNU General Public License as published by the Free 
-- Software Foundation, either version 3 of the License, or (at your option) 
-- any later version.
--
-- AURORA is distributed in the hope that it will be useful, but WITHOUT ANY 
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
-- FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with 
-- AURORA. If not, see <https://www.gnu.org/licenses/>. 
--
-- Database setup minimum data

-- Core data and definition tables
----------------------------------

-- ENTITY - Any thing in the system, its parent and type 
insert into ENTITY values
    (1,1,1), -- Root node
    (2,1,1), -- Global users
    (3,2,2), -- Global admin
    (4,1,1), -- Global groups
    (5,4,1)  -- Global admingroup
    ;
--
insert into ENTITYTYPE values
    (1,'GROUP'),
    (2,'USER'),
    (3,'DATASET'),
    (4,'COMPUTER'),
    (5,'TEMPLATE'),
    (6,'STORE'),
    (7,'INTERFACE'),
    (8,'NOTICE'),
    (9,'TASK')
    ;

-- METADATA - data assosiated to an entity
insert into METADATA values
    (1,1,1,'ROOT'),
    (2,1,1,'USERS'),
    (3,1,1,'admin'),
    (4,1,1,'GROUPS'),
    (5,1,1,'administrators')
    ;
--
insert into METADATAKEY values
    (1,'.system.entity.name')
    ;


-- Core permission stucture tables
----------------------------------

-- MEMBER - membership relation between entitys
insert into MEMBER values
    (3,5)
    ;

-- PERM - permission masks
insert into PERM values
    (5,1,x'ffffffffFFFFFFFF','')
    ;
--
insert into PERMTYPE values
    (1,'COMPUTER_MEMBER_ADD'),(2,'COMPUTER_CREATE'),(3,'COMPUTER_DELETE'),(4,'COMPUTER_CHANGE'),(5,'COMPUTER_MOVE'),
    (6,'COMPUTER_TEMPLATE_ASSIGN'),(7,'COMPUTER_PERM_SET'),(8,'DATASET_CREATE'),(9,'DATASET_DELETE'),(10,'DATASET_CHANGE'),
    (11,'DATASET_MOVE'),(12,'DATASET_PUBLISH'),(13,'DATASET_LOG_READ'),(14,'DATASET_RERUN'),(15,'DATASET_PERM_SET'),
    (16,'DATASET_READ'),(17,'GROUP_CREATE'),(18,'GROUP_DELETE'),(19,'GROUP_CHANGE'),(20,'GROUP_MOVE'),
    (21,'GROUP_MEMBER_ADD'),(22,'GROUP_TEMPLATE_ASSIGN'),(23,'GROUP_PERM_SET'),(24,'STORE_CREATE'),(25,'STORE_CHANGE'),
    (26,'TEMPLATE_CREATE'),(27,'TEMPLATE_DELETE'),(28,'TEMPLATE_CHANGE'),(29,'TEMPLATE_PERM_SET'),(30,'USER_CREATE'),
    (31,'USER_DELETE'),(32,'USER_CHANGE'),(33,'USER_MOVE'),(34,'USER_READ'),(35,'COMPUTER_FOLDER_LIST'),
    (36,'DATASET_LIST'),(37,'COMPUTER_READ'),(38,'DATASET_METADATA_READ'),(39,'NOTICE_DELETE'),(40,'NOTICE_MOVE'),
    (41,'NOTICE_CHANGE'),(42,'NOTICE_CREATE'),(43,'NOTICE_READ'),(44,'TASK_CREATE'),(45,'TASK_READ'),
    (46,'TASK_CHANGE'),(47,'TASK_MOVE'),(48,'TASK_DELETE'),(49,'TASK_PERM_SET'),(50,'TASK_EXECUTE'),
    (51,'DATASET_CLOSE'),(52,'DATASET_EXTEND_UNLIMITED'),(53,'COMPUTER_WRITE'),(54,'COMPUTER_REMOTE')
    ;


-- Data quality templates
-------------------------

-- TMPLASSIGN
-- TMPLCON
-- TMPLDEF
-- TMPLFLAG

-- History log
--------------

insert into LOGLEVEL values
    (1,'DEBUG'),(2,'INFORMATION'),(3,'WARNING'),(4,'ERROR'),(5,'FATAL')
    ;


-- File interface mode mapping

insert into FI_MODE select PERMTYPE,"rw" from PERMTYPE where PERMNAME="DATASET_CHANGE";
insert into FI_MODE select PERMTYPE,"ro" from PERMTYPE where PERMNAME="DATASET_READ";


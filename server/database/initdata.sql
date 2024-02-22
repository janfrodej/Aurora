-- Copyright (C) 2019-2024 Jan Frode JÃ¦ger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
-- Copyright (C) 2019-2024 BÃ¥rd Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
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
-- General, database engine-independent init-data for the 
-- AURORA-database
-- ------------------------------------------------------

--
-- Dumping data for table `ENTITY`
--

LOCK TABLES `ENTITY` WRITE;
/*!40000 ALTER TABLE `ENTITY` DISABLE KEYS */;
INSERT INTO `ENTITY` VALUES (1,1,1),
   (2,17,2),
   (3,27,6),
   (4,27,6),
   (5,27,6),
   (6,27,6),
   (7,27,6),
   (11,27,7),
   (13,27,7),
   (14,27,7),
   (15,27,8),
   (16,1,1),
   (17,16,1),
   (27,1,1),
   (28,1,1),
   (43,28,5),
   (45,16,1),
   (46,45,1),
   (88,27,4),
   (89,28,5),
   (90,28,5),
   (91,28,5),
   (92,28,5),
   (93,28,5),
   (96,1,9),
   (333,17,1),
   (439,28,5),
   (440,28,5),
   (441,28,5),
   (442,1,1),
   (443,28,5);
/*!40000 ALTER TABLE `ENTITY` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `ENTITYTYPE`
--

LOCK TABLES `ENTITYTYPE` WRITE;
/*!40000 ALTER TABLE `ENTITYTYPE` DISABLE KEYS */;
INSERT INTO `ENTITYTYPE` VALUES (1,'GROUP'),(2,'USER'),(3,'DATASET'),(4,'COMPUTER'),(5,'TEMPLATE'),(6,'STORE'),(7,'INTERFACE'),(8,'NOTICE'),(9,'TASK'),(10,'SCRIPT');
/*!40000 ALTER TABLE `ENTITYTYPE` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `LOG`
--

LOCK TABLES `LOG` WRITE;
/*!40000 ALTER TABLE `LOG` DISABLE KEYS */;
/*!40000 ALTER TABLE `LOG` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `LOGLEVEL`
--

LOCK TABLES `LOGLEVEL` WRITE;
/*!40000 ALTER TABLE `LOGLEVEL` DISABLE KEYS */;
INSERT INTO `LOGLEVEL` VALUES (1,'DEBUG'),(2,'INFORMATION'),(3,'WARNING'),(4,'ERROR'),(5,'FATAL');
/*!40000 ALTER TABLE `LOGLEVEL` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `MEMBER`
--

LOCK TABLES `MEMBER` WRITE;
/*!40000 ALTER TABLE `MEMBER` DISABLE KEYS */;
INSERT INTO `MEMBER` VALUES (2,46);
/*!40000 ALTER TABLE `MEMBER` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `METADATA`
--

LOCK TABLES `METADATA` WRITE;
/*!40000 ALTER TABLE `METADATA` DISABLE KEYS */;
INSERT INTO `METADATA` VALUES (1,21,1,'root'),
   (1,75,1,'1'),
   (1,76,1,'2'),
   (1,84,1,'1'),
   (1,85,1,'100'),
   (1,86,1,'1'),
   (1,87,1,'100'),
   (1,20,1,1),
   (1,22,1,3),
   (1,24,1,1),
   (1,166,1,'default'),
   (2,1,1,'Admin'),
   (2,17,1,'admin@localhost'),
   (2,21,1,'admin@localhost (Admin)'),
   (2,29,1,'$6$mUDMMYqeU/eLJ1vH$7Tiej9y55GXN0RMItWAcW/RnKKE0uS.oIFncnN6vT.mckMRQsRQ0gP5PaBIwqmNpPXZreFvRbFUDoez69eHPU/'),
   (2,30,1,'4102441200'),
   (2,69,1,'1610704579'),
   (2,82,1,'Admin'),
   (2,83,1,'admin@localhost'),
   (3,21,1,'Store::RSyncSSH'),
   (3,46,1,'Store::RSyncSSH'),
   (4,21,1,'Store::SCP'),
   (4,46,1,'Store::SCP'),
   (5,21,1,'Store::SFTP'),
   (5,46,1,'Store::SFTP'),
   (6,21,1,'Store::FTP'),
   (6,46,1,'Store::FTP'),
   (7,21,1,'Store::SMB'),
   (7,46,1,'Store::SMB'),
   (11,21,1,'Samba/CIFS'),
   (11,52,1,'Interface::CIFS'),
   (11,55,1,'10.0.10.13/datasets'),
   (13,21,1,'TAR-set'),
   (13,52,1,'Interface::Archive::tar'),
   (13,53,1,'/Aurora/dropzone'),
   (13,54,1,'https://auroradev/dl.cgi'),
   (14,21,1,'ZIP-set'),
   (14,52,1,'Interface::Archive::zip'),
   (14,53,1,'/Aurora/dropzone'),
   (14,54,1,'https://auroradev/dl.cgi'),
   (15,21,1,'Notice::Email'),
   (16,21,1,'NTNU'),
   (17,21,1,'users'),
   (27,21,1,'system'),
   (28,21,1,'templates'),
   (43,21,1,'DublinCore-specification'),
   (45,21,1,'roles'),
   (46,21,1,'Admins'),
   (88,21,1,'_NO NAME Computer'),
   (88,75,1,'/dev/null'),
   (88,31,1,'0'),
   (88,104,1,'dummy.localhost'),
   (89,21,1,'GLOBAL GROUP create'),
   (90,21,1,'GLOBAL USER create'),
   (91,21,1,'GLOBAL COMPUTER create'),
   (92,21,1,'GLOBAL TASK create'),
   (93,21,1,'GLOBAL TEMPLATE create'),
   (96,21,1,'GLOBAL RSyncSSH-task'),
   (96,106,1,'id_rsa.keyfile'),
   (96,107,1,'RSyncSSH Task'),
   (96,108,1,'Administrator'),
   (96,109,1,'4'),
   (96,110,1,'3'),
   (96,111,1,'22'),
   (333,20,1,623),
   (333,21,1,"Zombie Limbo"),
   (333,22,1,1),
   (333,24,1,17),
   (439,21,1,'GLOBAL Dataset Extend Policy'),
   (439,124,1,'5'),
   (439,125,1,'439'),
   (439,126,1,'28'),
   (440,21,1,'GLOBAL Dataset Lifespan Policy'),
   (440,124,1,'5'),
   (440,125,1,'440'),
   (440,126,1,'28'),
   (441,21,1,'GLOBAL Notification Intervals'),
   (441,124,1,'5'),
   (441,125,1,'441'),
   (441,126,1,'28'),
   (442,21,1,'scripts'),
   (443,21,1,'GLOBAL SCRIPT create'),
   (443,20,1,443),
   (443,22,1,5),
   (443,24,1,442);
/*!40000 ALTER TABLE `METADATA` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `METADATAKEY`
--

LOCK TABLES `METADATAKEY` WRITE;
/*!40000 ALTER TABLE `METADATAKEY` DISABLE KEYS */;
INSERT INTO `METADATAKEY` VALUES (1,'.Creator'),
   (2,'.Contributor'),
   (3,'.Publisher'),
   (4,'.Title'),
   (5, '.Date'),
   (6,'.Language'),
   (7,'.Format'),
   (8,'.Subject'),
   (9,'.Description'),
   (10,'.Identifier'),
   (11,'.Relation'),
   (12,'.Source'),
   (13,'.Type'),
   (14,'.Coverage'),
   (15,'.Rights'),
   (17,'system.user.username'),
   (20,"system.entity.id"),
   (21,".system.entity.name"),
   (22,"system.entity.typeid"),
   (23,"system.entity.typename"),
   (24,"system.entity.parentid"),
   (25,"system.entity.parentname"),
   (26,"system.dataset.computerid"),
   (27,"system.dataset.computername"),
   (29,'system.authenticator.auroraid.authstr'),
   (30,'system.authenticator.auroraid.expire'),
   (31,'.computer.useusername'),
   (46,'system.store.class'),
   (52,'system.interface.class'),
   (53,'system.interface.classparam.location'),
   (54,'system.interface.classparam.script'),
   (55,'system.interface.classparam.base'),
   (69,'system.user.lastlogon'),
   (73,'system.computer.storecollection.get.1.param.host'),
   (74,'system.computer.storecollection.get.1.param.knownhosts'),
   (75,'.computer.path'),
   (76,'system.computer.storecollection.get.1.store'),
   (77,'system.computer.storecollection.get.1.name'),
   (78,'system.computer.storecollection.get.1.param.username'),
   (79,'system.computer.storecollection.get.1.param.privatekeyfile'),
   (80,'system.computer.storecollection.get.1.param.port'),
   (81,'system.computer.storecollection.get.1.classparam.authmode'),
   (82,'system.user.fullname'),
   (83,'system.authenticator.oauthaccesstoken.user'),
   (84,'system.notice.subscribe.2.0'),
   (85,'system.notice.votes.2'),
   (104,'.system.task.param.host'),
   (105,'.system.task.param.knownhosts'),
   (106,'system.task.definition.get.1.param.privatekeyfile'),
   (107,'system.task.definition.get.1.name'),
   (108,'system.task.definition.get.1.param.username'),
   (109,'system.task.definition.get.1.classparam.authmode'),
   (110,'system.task.definition.get.1.store'),
   (111,'system.task.definition.get.1.param.port'),
   (127,'system.dataset.open.extendlimit'),
   (128,'system.dataset.open.extendmax'),
   (129,'system.dataset.close.extendlimit'),
   (130,'system.dataset.close.extendmax'),
   (132,'system.dataset.close.lifespan'),
   (133,'system.dataset.notification.intervals'),
   (131,'system.dataset.open.lifespan'),
   (166,'system.fileinterface.store');
/*!40000 ALTER TABLE `METADATAKEY` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `PERM`
--

LOCK TABLES `PERM` WRITE;
/*!40000 ALTER TABLE `PERM` DISABLE KEYS */;
INSERT INTO `PERM` VALUES (46,1,'þÿÿÿÿÿ','');
/*!40000 ALTER TABLE `PERM` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `PERMTYPE`
--

LOCK TABLES `PERMTYPE` WRITE;
/*!40000 ALTER TABLE `PERMTYPE` DISABLE KEYS */;
INSERT INTO `PERMTYPE` VALUES (1,'COMPUTER_MEMBER_ADD'),
   (2,'COMPUTER_CREATE'),
   (3,'COMPUTER_DELETE'),
   (4,'COMPUTER_CHANGE'),
   (5,'COMPUTER_MOVE'),
   (6,'COMPUTER_TEMPLATE_ASSIGN'),
   (7,'COMPUTER_PERM_SET'),
   (8,'DATASET_CREATE'),
   (9,'DATASET_DELETE'),
   (10,'DATASET_CHANGE'),
   (11,'DATASET_MOVE'),
   (12,'DATASET_PUBLISH'),
   (13,'DATASET_LOG_READ'),
   (14,'DATASET_RERUN'),
   (15,'DATASET_PERM_SET'),
   (16,'DATASET_READ'),
   (17,'GROUP_CREATE'),
   (18,'GROUP_DELETE'),
   (19,'GROUP_CHANGE'),
   (20,'GROUP_MOVE'),
   (21,'GROUP_MEMBER_ADD'),
   (22,'GROUP_TEMPLATE_ASSIGN'),
   (23,'GROUP_PERM_SET'),
   (24,'STORE_CREATE'),
   (25,'STORE_CHANGE'),
   (26,'TEMPLATE_CREATE'),
   (27,'TEMPLATE_DELETE'),
   (28,'TEMPLATE_CHANGE'),
   (29,'TEMPLATE_PERM_SET'),
   (30,'USER_CREATE'),
   (31,'USER_DELETE'),
   (32,'USER_CHANGE'),
   (33,'USER_MOVE'),
   (34,'USER_READ'),
   (35,'COMPUTER_FOLDER_LIST'),
   (36,'DATASET_LIST'),
   (37,'COMPUTER_READ'),
   (38,'DATASET_METADATA_READ'),
   (39,'NOTICE_DELETE'),
   (40,'NOTICE_MOVE'),
   (41,'NOTICE_CHANGE'),
   (42,'NOTICE_CREATE'),
   (43,'NOTICE_READ'),
   (44,'TASK_CREATE'),
   (45,'TASK_READ'),
   (46,'TASK_CHANGE'),
   (47,'TASK_MOVE'),
   (48,'TASK_DELETE'),
   (49,'TASK_PERM_SET'),
   (50,'TASK_EXECUTE'),
   (51,'DATASET_CLOSE'),
   (52,'DATASET_EXTEND_UNLIMITED'),
   (53,'COMPUTER_WRITE'),
   (54,'COMPUTER_REMOTE'),
   (55,'GROUP_FILEINTERFACE_STORE_SET'),
   (56,'SCRIPT_CREATE'),
   (57,'SCRIPT_DELETE'),
   (58,'SCRIPT_CHANGE'),
   (59,'SCRIPT_READ'),
   (60,'SCRIPT_MOVE'),
   (61,'SCRIPT_PERM_SET');
/*!40000 ALTER TABLE `PERMTYPE` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `TMPLASSIGN`
--

LOCK TABLES `TMPLASSIGN` WRITE;
/*!40000 ALTER TABLE `TMPLASSIGN` DISABLE KEYS */;
INSERT INTO `TMPLASSIGN` VALUES (1,1,1,89),
   (1,2,1,90),
   (1,3,1,440),
   (1,3,2,441),
   (1,3,3,439),
   (1,3,4,43),
   (1,4,1,91),
   (1,5,1,93),
   (1,9,1,92),
   (1,10,1,443);
/*!40000 ALTER TABLE `TMPLASSIGN` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `TMPLCON`
--

LOCK TABLES `TMPLCON` WRITE;
/*!40000 ALTER TABLE `TMPLCON` DISABLE KEYS */;
INSERT INTO `TMPLCON` VALUES (43,1,'[^\\000-\\037\\177]*','',1,0,'This field type describes the creator(s) of the dataset. It accepts any non-special characters'),
   (43,2,'[^\\000-\\037\\177]*',NULL,0,0,'This field type describes who has contributed to the creation of the dataset. It accepts any non-special characters'),
   (43,3,'[^\\000-\\037\\177]*','\0',0,0,'This field type contains the publisher(s) of the dataset.'),
   (43,4,'[^\\000-\\037\\177]*','\0',0,1,'This field type describes the title of the dataset. It accepts any non-special characters'),
   (43,5,'[0-9]{4}\\-(0[1-9]|1[0-2])\\-(0[1-9]|[12][0-9]|3[01])T(0[0-9]|[1][0-9]|2[0-3])\\:(0[0-9]|[1-5][0-9])\\:(0[0-9]|[1-5][0-9])((Z|(\\+(0[0-9]|1[0-4])|\\-(0[0-9]|1[0-2]))\\:(0[0-9]|[1-5][0-9])))','',1,1,'This field type contains the date(s) of the dataset. Primarily the creation date. All date entries must comply with the ISO-8601 standard.'),
   (43,6,'[a-z]*','X',1,0,'This field type contains language(s) of the dataset in accordance with the ISO-639-2 standard.'),
   (43,7,'[^\\000-\\037\\177]*','\0',0,0,'This field type contains format(s) of the dataset, such as file formats of its content.'),
   (43,8,'[^\\000-\\037\\177]+','X',1,1,'This field type contains the subject(s) of the dataset, such as Chemistry, Physics etc.'),
   (43,9,'[^\\000-\\037\\177]+','',1,1,'This field type describes what the dataset contains. Accepts any non-special characters'),
   (43,10,'[^\\000-\\037\\177]*','\0',0,0,'This field type contains identifier(s) of the dataset, such as DOI.'),
   (43,11,'[^\\000-\\037\\177]*','\0',0,0,'This field type contains relation(s) of the dataset.'),
   (43,12,'[^\\000-\\037\\177]*','\0',0,0,'This field type contains source(s) of the dataset, such as earlier versions of the dataset.'),
   (43,13,'[^\\000-\\037\\177]+','X',1,1,'This field type contains the type(s) of the dataset.'),
   (43,14,'[^\\000-\\037\\177]*','\0',0,1,'This field type contains the coverage of the dataset'),
   (43,15,'[^\\000-\\037\\177]+',NULL,1,1,'This field type describes the rights/copyright of the dataset. It accepts any non-special characters'),
   (89,21,'[^\\000-\\037\\177]+','',1,1,'Name of the GROUP. Accepts all non-special characters'),
   (90,17,'[a-zA-Z]{1}[a-zA-Z0-9\\.\\!\\#$\\%\\&\\\'\\*\\+\\-\\/\\=\\?\\^\\_\\`\\{\\|\\}\\~]*\\@[a-zA-Z0-9\\-\\.]+','',1,1,'USER\'s username (email address)'),
   (90,82,'[^\\000-\\037\\177]+','',1,1,'USER\'s full name (first and last name). Accepts all non-special characters'),
   (91,21,'[^\\000-\\037\\177]+','',1,1,'COMPUTER\'s display name. Accepts all non-special characters'),
   (91,31,'[0-1]{1}','^X',1,1,'Sets if the COMPUTERS path is to be post-fixed with the username (email) of the user that is creating/acquiring/distributing a dataset. Valid values are 0 (disabled) or 1 (enabled)'),
   (91,75,'[^\\000]*','',0,1,'COMPUTER\'s full and absolute local path to where data resides on the computer. Needed in the case of ASYNC archiving runs'),
   (91,104,'[a-zA-Z0-9\\:\\.\\-]{1,63}','',1,1,'COMPUTER host-name'),
   (91,105,'[^\\000-\\037\\177]*','',1,1,'COMPUTER public key with host-name as in a known_hosts-file'),
   (92,21,'[^\\000-\\037\\177]+','',1,1,'Sets the name of the TASK. Accepts all non-special characters'),
   (93,21,'[^\\000-\\037\\177]+','',1,1,'Name of the TEMPLATE. Accepts all non-special characters'),
   (439,127,'\\d+',NULL,1,1,''),
   (439,128,'\\d+',NULL,1,1,''),
   (439,129,'\\d+',NULL,1,1,''),
   (439,130,'\\d+',NULL,1,1,''),
   (440,131,'\\d+',NULL,1,1,''),
   (440,132,'\\d+',NULL,1,1,''),
   (441,133,'\\d+',NULL,1,0,''),
   (443,21,'[^\\000-\\037\\177]+','^X',1,1,'Sets the name of the SCRIPT. Accepts any non-special characters.');
/*!40000 ALTER TABLE `TMPLCON` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `TMPLDEF`
--

LOCK TABLES `TMPLDEF` WRITE;
/*!40000 ALTER TABLE `TMPLDEF` DISABLE KEYS */;
INSERT INTO `TMPLDEF` VALUES (43,1,1,''),
   (43,2,1,''),
   (43,3,1,''),
   (43,4,1,''),
   (43,5,1,''),
   (43,6,1,'eng'),
   (43,6,2,'nor'),
   (43,6,3,'swe'),
   (43,6,4,'dan'),
   (43,6,5,'fin'),
   (43,6,6,'fre'),
   (43,6,7,'ger'),
   (43,6,8,'spa'),
   (43,6,9,'ita'),
   (43,6,10,'ara'),
   (43,7,1,''),
   (43,8,1,'Physics'),
   (43,8,2,'Agricultural Sciences'),
   (43,8,3,'Arts and Humanities'),
   (43,8,4,'Astronomy and Astrophysics'),
   (43,8,5,'Business and Management'),
   (43,8,6,'Chemistry'),
   (43,8,7,'Computer and Information Science'),
   (43,8,8,'Earth and Environmental Sciences'),
   (43,8,9,'Engineering'),
   (43,8,10,'Law'),
   (43,8,11,'Mathematical Sciences'),
   (43,8,12,'Medicine, Health and Life Sciences'),
   (43,8,13,'Social Sciences'),
   (43,8,14,'Other'),
   (43,9,1,''),
   (43,10,1,''),
   (43,11,1,''),
   (43,12,1,''),
   (43,13,1,'Dataset'),
   (43,14,1,''),
   (43,15,1,'Copyright(C) NTNU, Trondheim, Norway'),
   (89,21,1,NULL),
   (90,17,1,''),
   (90,82,1,''),
   (91,21,1,''),
   (91,31,1,0),
   (91,75,1,''),
   (91,104,1,''),
   (91,105,1,''),
   (92,21,1,''),
   (93,21,1,''),
   (439,127,1,'604800'),
   (439,128,1,'86400'),
   (439,129,1,'15552000'),
   (439,130,1,'1209600'),
   (440,131,1,'259200'),
   (440,132,1,'15552000'),
   (441,133,1,'86400'),
   (441,133,2,'604800'),
   (441,133,3,'1209600'),
   (441,133,4,'2592000'),
   (443,21,1,'');
/*!40000 ALTER TABLE `TMPLDEF` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping data for table `TMPLFLAG`
--

LOCK TABLES `TMPLFLAG` WRITE;
/*!40000 ALTER TABLE `TMPLFLAG` DISABLE KEYS */;
INSERT INTO `TMPLFLAG` VALUES (3,'MANDATORY'),(4,'NONOVERRIDE'),(6,'SINGULAR'),(7,'MULTIPLE'),(8,'OMIT'),(9,'PERSISTENT');
/*!40000 ALTER TABLE `TMPLFLAG` ENABLE KEYS */;
UNLOCK TABLES;

-- File interface mode mapping

LOCK TABLES `FI_MODE` WRITE, `PERMTYPE` READ;
insert into FI_MODE select PERMTYPE,"rw" from PERMTYPE where PERMNAME="DATASET_CHANGE";
insert into FI_MODE select PERMTYPE,"ro" from PERMTYPE where PERMNAME="DATASET_READ";
UNLOCK TABLES;

-- Copyright (C) 2019-2024 Bård Tesaker <bard.tesaker@ntnu.no>, NTNU, Trondheim, Norway
-- Copyright (C) 2019-2024 Jan Frode Jæger <jan.frode.jaeger@ntnu.no>, NTNU, Trondheim, Norway
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
-- Database setup file

/*
Tables is classified like this:
- No drop statement: contain user data
- Commented out drop statements: Contain configuration or history 
- drop statement: May be rebuild, with varying disruption
- clustered drop's: Rebuild these tables/views together
*/

/*******************
*  MySQL settings  *
*******************/



/********************
*  Data structures  *
********************/


-- Core data and definition tables
----------------------------------

-- ENTITY - Any thing in the system, its parent and type 
create table ENTITY(
    entity bigint primary key auto_increment,
    entityparent bigint not NULL,
    entitytype bigint not NULL
    );
--
drop table ENTITYTYPE;
create table ENTITYTYPE(
    entitytype bigint primary key auto_increment,
    entitytypename varchar(255) not NULL
    );

-- METADATA - data assosiated to an entity
create table METADATA(
    entity bigint,
    metadatakey bigint,
    metadataidx bigint,
    metadataval varchar(1024),
    primary key (entity,metadatakey,metadataidx),
    key metadataval (metadataval)
    );
--
drop table METADATAKEY;
create table METADATAKEY(
    metadatakey bigint primary key auto_increment,
    metadatakeyname varchar(1024) not NULL,
    key metadatakeyname (metadatakeyname)
    );
-- METADATA_COMBINED - METADATA-table + synthetic data
create table METADATA_COMBINED(
    entity bigint,
    metadatakey bigint,
    metadataidx bigint,
    metadataval varchar(1024),
    primary key (entity,metadatakey,metadataidx),
    key metadataval (metadataval)
    );

-- Core permission stucture tables
----------------------------------

-- MEMBER - membership relation between entitys
create table MEMBER(
    membersubject bigint,
    memberobject bigint,
    primary key (membersubject,memberobject)
    );

-- PERM - permission masks
create table PERM(
    permsubject bigint,
    permobject bigint,
    permgrant blob,
    permdeny blob,
    primary key (permsubject,permobject)
    );
--
drop table PERMTYPE;
create table PERMTYPE(
    PERMTYPE bigint primary key auto_increment,
    PERMNAME varchar(255)
    );

-- Data quality templates
-------------------------

-- TMPLASSIGN
create table TMPLASSIGN(
    tmplassignentity bigint,
    tmplassigntype bigint,
    tmplassignno bigint,
    tmpl bigint,
    primary key(tmplassignentity,tmplassigntype,tmplassignno)
    );
    
-- TMPLCON
create table TMPLCON(
    tmpl bigint,
    tmplconkey bigint,
    tmplconregex varchar(255),
    tmplconflags varchar(255),
    tmplconmin bigint,
    tmplconmax bigint,
    tmplconcom varchar(255),
    primary key(tmpl,tmplconkey)
    );
    
-- TMPLDEF
create table TMPLDEF(
    tmpl bigint,
    tmplconkey bigint,
    tmpldefno bigint,
    tmpldef varchar(1024),
    primary key(tmpldefno,tmpl,tmplconkey)
    );

-- TMPLFLAG
create table TMPLFLAG(
    tmplflag int(10) primary key,
    tmplflagname varchar(32),
    );

-- History log
--------------

-- drop table LOG;
create table LOG(
    logidx bigint primary key auto_increment,
    logtime double,
    entity bigint,
    loglevel int,
    logmess varchar(1024)
);
--
drop table LOGLEVEL;
create table LOGLEVEL(
    loglevel bigint primary key auto_increment,
    loglevelname varchar(50) not NULL
);
--
drop table USERLOG;
create table USERLOG(
    logidx bigint primary key auto_increment,
    logtime double,
    entity bigint,
    tag varchar(15),
    message varchar(1024)
);

/****************************
*  Derived tables and views *
****************************/

-- DEPTH view to get tree depth of entities
drop view DEPTH;
create view DEPTH as AS select `ANCESTORS`.`entity` AS `entity`,count(`ANCESTORS`.`ancestor`) AS `depth` from `ANCESTORS` group by `ANCESTORS`.`entity`;

-- Modification times (maitained by AuroraDB::setMtime)
drop table MTIME;
create table MTIME(
    table_name varchar(255) primary key,
    mtime double
    );

-- Entity structural sequence (maitained by AuroraDB::sequenceEntity)
drop table ENTITY_SEQUENCE;
create table ENTITY_SEQUENCE(
    sequence bigint primary key auto_increment,
    entity bigint
    );

-- Permission related views and tables
--------------------------------------

-- ANCESTORS - Entitys ancestors including it self
drop view ANCESTORS_0;
drop view ANCESTORS_1;
drop view ANCESTORS_2;
drop view ANCESTORS_3;
drop view ANCESTORS_4;
drop view ANCESTORS_5;
drop view ANCESTORS_6;
drop view ANCESTORS_7;
drop view ANCESTORS_8;
drop view ANCESTORS_9;
drop view ANCESTORS;
create view ANCESTORS_0 as select entity,entity as ancestor from ENTITY;
create view ANCESTORS_1 as select a.entity,entityparent as ancestor from ANCESTORS_0 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS_2 as select a.entity,entityparent as ancestor from ANCESTORS_1 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS_3 as select a.entity,entityparent as ancestor from ANCESTORS_2 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS_4 as select a.entity,entityparent as ancestor from ANCESTORS_3 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS_5 as select a.entity,entityparent as ancestor from ANCESTORS_4 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS_6 as select a.entity,entityparent as ancestor from ANCESTORS_5 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS_7 as select a.entity,entityparent as ancestor from ANCESTORS_6 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS_8 as select a.entity,entityparent as ancestor from ANCESTORS_7 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS_9 as select a.entity,entityparent as ancestor from ANCESTORS_8 as a join ENTITY as e on a.ancestor=e.entity where e.entity!=e.entityparent;        
create view ANCESTORS as
    select       * from ANCESTORS_0
    union select * from ANCESTORS_1
    union select * from ANCESTORS_2
    union select * from ANCESTORS_3
    union select * from ANCESTORS_4
    union select * from ANCESTORS_5
    union select * from ANCESTORS_6
    union select * from ANCESTORS_7
    union select * from ANCESTORS_8
    union select * from ANCESTORS_9
    ;

-- ROLES - Cascading membership roles from all ancestors
drop view ROLES;
drop view ROLES_0;
drop view ROLES_1;
drop view ROLES_2;
drop view ROLES_3;
drop view ROLES_4;
drop view ROLES_5;
drop view ROLES_6;
drop view ROLES_7;
drop view ROLES_8;
drop view ROLES_9;
create view ROLES_0 as select entity,ancestor as role from ANCESTORS;
create view ROLES_1 as select r.entity as entity,m.memberobject as role from ROLES_0 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES_2 as select r.entity as entity,m.memberobject as role from ROLES_1 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES_3 as select r.entity as entity,m.memberobject as role from ROLES_2 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES_4 as select r.entity as entity,m.memberobject as role from ROLES_3 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES_5 as select r.entity as entity,m.memberobject as role from ROLES_4 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES_6 as select r.entity as entity,m.memberobject as role from ROLES_5 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES_7 as select r.entity as entity,m.memberobject as role from ROLES_6 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES_8 as select r.entity as entity,m.memberobject as role from ROLES_7 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES_9 as select r.entity as entity,m.memberobject as role from ROLES_8 as r join MEMBER as m on m.membersubject=r.role;
create view ROLES as
    select * from ROLES_0
    union select * from ROLES_1
    union select * from ROLES_2
    union select * from ROLES_3
    union select * from ROLES_4
    union select * from ROLES_5
    union select * from ROLES_6
    union select * from ROLES_7
    union select * from ROLES_8
    union select * from ROLES_9
    ;

-- PERMISSIONS - All relevant grants and denys for an subjec,object pair
drop view PERMISSIONS;
create view PERMISSIONS as
    select
        r.entity as permsubject,
        a.entity as permobject,
        s.sequence as sequence,
        p.permgrant,
        p.permdeny
    from PERM as p
    join ENTITY_SEQUENCE as s on s.entity=p.permobject
    join ROLES as r on r.role=p.permsubject
    join ANCESTORS as a on a.ancestor=p.permobject
    order by s.sequence
    ;

-- PERM_EFFECTIVE - cache table for effective pemissions (maintained by AuroraDB::updateEffectivePerms)
drop table PERM_EFFECTIVE_PERMS;
drop table PERM_EFFECTIVE_LUT;
create table PERM_EFFECTIVE_PERMS(
    permsubject int(11),
    permobject int(11),
    perms blob,
    primary key (permsubject,permobject)
    );
create table PERM_EFFECTIVE_LUT(
    perms blob,
    perm int(11),
    primary key (perms(32),perm) 
    );
--
drop view PERM_EFFECTIVE;
create view PERM_EFFECTIVE as
   select
       p.permsubject as permsubject,
       p.permobject as permobject,
       l.perm as perm
   from PERM_EFFECTIVE_PERMS p
   join `PERM_EFFECTIVE_LUT` l on l.perms= p.perms
   ;

-- File Interface cache tables

drop table FI_MODE;
create table FI_MODE(
    perm integer primary key,
    mode varchar(32)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- drop table FI_DATASET;
create table FI_DATASET(
    entity bigint primary key,
    store varchar(32),
    perm integer,
    cookie varchar(255),
    timestamp double
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

drop view FI_SCALE;
create view FI_SCALE as
    select
        entity,
        concat(
            substr((floor(entity/1000000) % 1000)+1000,2,3),
            "/",
            substr((floor(entity/1000) % 1000)+1000,2,3)
            ) as scale
    from FI_DATASET
    ;


drop view FI_PATH;
create view FI_PATH as
    select
        concat("fi-",     store, "/rw/",        scale)                                      as rwscale,
        concat("fi-",     store, "/ro/",        scale)                                      as roscale,
        concat("rm-",     store, "/",           scale)                                      as rmscale,
        concat("fi-",     store, "/", mode,"/", scale, "/", entity)                         as fipath,
        concat("fi-",     store, "/", mode,"/", scale, "/", entity, "/", cookie)            as fiprivate,
        concat("rw-",     store, "/",           scale, "/", entity)                         as rwpath,
        concat("ro-",     store, "/",           scale, "/", entity)                         as ropath,
        concat("rm-",     store, "/",           scale, "/", entity)                         as rmpath,
        concat(mode, "-", store, "/",           scale, "/", entity)                         as linkpath,
        concat("view/",                         scale, "/", entity, "/", cookie)            as privatepath,
        concat("view/",                         scale, "/", entity, "/", cookie, "/data")   as datapath,
        entity as dataset
    from             FI_DATASET
        natural join FI_SCALE
        natural join FI_MODE
    ;

drop view FI_INFO;
create view FI_INFO as
    select
        D.entity     as entity,
        S.scale      as scale,
        D.store      as store,
        M.perm       as perm,
        M.mode       as mode,
        D.cookie     as cookie,
        D.timestamp  as timestamp,
        concat("view/",           S.scale, "/", D.entity)                         as datasetpath,
        concat("view/",           S.scale)                                        as viewscale,
        P.*
    from          FI_DATASET D
             join FI_SCALE   S on S.entity=D.entity
        left join FI_MODE    M on M.perm=D.perm
        left join FI_PATH    P on P.dataset=D.entity
    ;

-- drop table FI_SUBJECT;
create table FI_SUBJECT(
    subject bigint primary key,
    keycode varchar(255),
    username varchar(255),
    uid bigint
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

drop view FI_KEYRING;
create view FI_KEYRING as
    select
        E.entity as subject,
        concat("view/", scale, "/", E.entity, "-", keycode) as keyring
    from          ENTITY     E
             join FI_SCALE   S on S.entity=E.entity
        left join FI_SUBJECT K on K.subject=E.entity
    ;

-- drop table FI_GRANTED;
create table FI_GRANTED(
    subject bigint,
    dataset bigint,
    perm    integer,
    primary key (subject,dataset)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

drop view FI_PERM;
create view FI_PERM as
    select
        E.permsubject as subject,
        E.permobject as dataset,
        E.perm as perm
    from
         FI_DATASET     D
    join PERM_EFFECTIVE E on E.permobject=D.entity and E.perm=D.perm
    ;

drop view FI_DENY;
create view FI_DENY as
    select
        G.*,
        S.keycode,
        S.username,
        S.uid,
        I.privatepath
    from
                  FI_GRANTED G
        left join FI_PERM    P on P.subject=G.subject and P.dataset=G.dataset and P.perm=G.perm
        left join FI_SUBJECT S on S.subject=G.subject
        left join FI_INFO    I on I.entity=G.dataset
    where P.perm is NULL
    ;

drop view FI_GRANT;
create view FI_GRANT as
    select
        P.*,
        S.keycode,
        S.username,
        S.uid,
        I.privatepath
    from
                  FI_PERM    P
        left join FI_GRANTED G on G.subject=P.subject and G.dataset=P.dataset and G.perm=P.perm
        left join FI_SUBJECT S on S.subject=P.subject
        left join FI_INFO    I on I.entity=P.dataset
    where G.perm is NULL
    ;


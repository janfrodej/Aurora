// Copyright (C) 2021-2024 Jan Frode Jæger (jan.frode.jaeger@ntnu.no), NTNU, Trondheim, Norway
//
// This file is part of AURORA, a system to store and manage science data.
//
// AURORA is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// AURORA is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// AURORA. If not, see <https://www.gnu.org/licenses/>.
//
// Description: AURORA database schema data which tells where to find and store metadata.
//
// System-Wide Definitions
//
// AURORA metadata namespace definitions
export const MD={    
    "computer_username"       : ".system.task.param.username",
    "dataset_status"          : "system.dataset.status",
    "dataset_distbase"        : "system.distribution",
    "dataset_created"         : "system.dataset.time.created",
    "dataset_progress"        : "system.dataset.time.progress",
    "dataset_closed"          : "system.dataset.time.closed",
    "dataset_expire"          : "system.dataset.time.expire",
    "dataset_tokenbase"       : "system.dataset.token",
    "dataset_removed"         : "system.dataset.time.removed",
    "dataset_archived"        : "system.dataset.time.archived",
    "dataset_retry"           : "system.dataset.retry",
    "dataset_type"            : "system.dataset.type",
    "dataset_creator"         : "system.dataset.creator",
    "dataset_computer"        : "system.dataset.computerid",
    "dataset_computername"    : "system.dataset.computername",
    "dataset_size"            : "system.dataset.size",
    "entity_parent"           : "system.entity.parentid",
    "entity_parentname"       : "system.entity.parentname",
    "entity_id"               : "system.entity.id",
    "fi_store"                : "system.fileinterface.store",
    "name"                    : ".system.entity.name",
    "entity_type"             : "system.entity.typeid",
    "entity_typename"         : "system.entity.typename",
    "dc_creator"              : ".Creator",
    "dc_description"          : ".Description",
    "dc_date"                 : ".Date",
    "fi.store"                : "system.fileinterface.store",
};

// Dublin-Core presets
export const PRESETS_DC={ 
    ".Creator": "Dublin Core Creator",
    ".Contributor": "Dublin Core Contributor",
    ".Publisher": "Dublin Core Publisher",
    ".Title": "Dublin Core Title",
    ".Date": "Dublin Core Date",
    ".Language": "Dublin Core Language",
    ".Format": "Dublin Core Format",
    ".Subject": "Dublin Core Subject",
    ".Description": "Dublin Core Description",
    ".Identifier": "Dublin Core Identifier",
    ".Relation": "Dublin Core Relation",
    ".Source": "Dublin Core Source",
    ".Type": "Dublin Core Type",
    ".Coverage": "Dublin Core Coverage",
    ".Rights": "Dublin Core Rights",    
};

// Presets for entity type COMPUTER
export let PRESETS_COMPUTER = JSON.parse(JSON.stringify(PRESETS_DC));
// add more presets to computer
PRESETS_COMPUTER[MD["computer_username"]]="Computer Login Username";

// Dublin-core and system presets
// copy dublin-core from previous structure
export let PRESETS_SYSTEM = JSON.parse(JSON.stringify(PRESETS_DC));
// add more presets
PRESETS_SYSTEM[MD["dataset_closed"]]="Time of dataset closure ("+MD["dataset_closed"]+")";
PRESETS_SYSTEM[MD["dataset_created"]]="Time of dataset creation ("+MD["dataset_created"]+")";
PRESETS_SYSTEM[MD["dataset_expire"]]="Time of dataset expiration ("+MD["dataset_expire"]+")";
PRESETS_SYSTEM[MD["dataset_removed"]]="Time of dataset removal ("+MD["dataset_removed"]+")";
PRESETS_SYSTEM[MD["dataset_status"]]="Dataset status - OPEN/CLOSED ("+MD["dataset_status"]+")";
PRESETS_SYSTEM[MD["dataset_size"]]="Dataset size ("+MD["dataset_size"]+")";
PRESETS_SYSTEM[MD["dataset_creator"]]="Dataset creator user ID ("+MD["dataset_creator"]+")";
PRESETS_SYSTEM[MD["dataset_computer"]]="Dataset source-computer ID ("+MD["dataset_computer"]+")";
PRESETS_SYSTEM[MD["dataset_computername"]]="Dataset source-computer name ("+MD["dataset_computername"]+")";
PRESETS_SYSTEM[MD["dataset_type"]]="Dataset type ("+MD["dataset_type"]+")";
PRESETS_SYSTEM[MD["entity_id"]]="Dataset ID ("+MD["entity_id"]+")";
PRESETS_SYSTEM[MD["entity_parent"]]="Dataset owner group ID ("+MD["entity_parent"]+")";
PRESETS_SYSTEM[MD["entity_parentname"]]="Dataset owner group name ("+MD["entity_parentname"]+")";
PRESETS_SYSTEM[".Project"]="Project name (.Project)";

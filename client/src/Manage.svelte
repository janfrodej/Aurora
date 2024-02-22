<!--
   Copyright (C) 2021-2024 Jan Frode Jæger (jan.frode.jaeger@ntnu.no), NTNU, Trondheim, Norway

    This file is part of AURORA, a system to store and manage science data.

    AURORA is free software: you can redistribute it and/or modify it under
    the terms of the GNU General Public License as published by the Free
    Software Foundation, either version 3 of the License, or (at your option)
    any later version.

    AURORA is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with
    AURORA. If not, see <https://www.gnu.org/licenses/>.
-->
<script> 
    import { getConfig } from "./_config";            
    import { onMount } from 'svelte';
    import { call_aurora } from "./_aurora.js";   
    import { AuroraDatasetCache } from "./_auroradatasetcache.js";
    import { ISO2Unixtime, unixtime2ISO } from "./_iso8601";
    import Icon from "./Icon.svelte";
    import Table from "./Table.svelte";
    import Modal from "./Modal.svelte";
    import MetadataEditor from "./MetadataEditor.svelte";   
    import Permissions from "./Permissions.svelte";
    import Close from "./Close.svelte";
    import Remove from "./Remove.svelte";
    import Log from "./Log.svelte";
    import Retrieve from "./Retrieve.svelte";
    import Expire from "./Expire.svelte";
    import Status from "./Status.svelte";
    import Ack from "./Ack.svelte";
    import { route, routeparams } from "./_stores";
    import { getCookieValue, setCookieValue, string2Boolean, string2Number } from "./_cookies";
    import SqlStructEditor from "./SQLStructEditor.svelte";
    import { MD } from "./_sysschema";
    import { SI2Int } from "./_tools";

    let CFG={};
    let disabled=false;           
    let headers={};
    let data;
    let search={};    
    let searching=false;  
    const sstructtmpl=["AND"];
    let searchstruct=sstructtmpl;
    let quicksearch="";
    let update = 0;
    let optupdated = false;

    let offset=1;  
    let count=10;
    let inclrm=false;
    let sortby="system.dataset.time.created";
    let sortdir="DESC";
    let sortdirint=-1;
    let sorttype=0;
    let total=0;
    let speed=0;
    let showsearchbar=false;
    let showMetadata=false;
    let metadatafinished=true;
    let showMetadataRO=false;
    let showExpire=false;
    let showPermissions=false;
    let showClose=false;
    let showRemove=false;
    let showRetrieve=false;
    let showLog=false;
    let showAck=false;
    let id=0;
    let rid="";
    let iddata={};  
    let routestr="";
    let routepars={};
    // cache
    let cache;

    route.subscribe(value => { routestr = value; });
    routeparams.subscribe(value => { routepars = value; });
    
    // return if a given dropdown choice is 
    // disabled or not for a given row
    // field - header definition for the row in question
    // menuitem - the hash structure for the dropdown option in question
    // rowdata - data structure of the row in question
    const handleDisabled = (field,menu,rowdata) => {
        // check which field we are checking the disabled flag of
        if (field.name == "Modify") {
            if (menu.name == "Close..") {
                // close is the menu choice
                if ((rowdata.perm.includes("DATASET_CLOSE")) &&
                    (rowdata.type == "MANUAL") &&
                    (rowdata.status == "OPEN")) {
                        return false;
                    } else { return true; }
            } else if (menu.name == "Expire Date..") {
                // expire date is the menu choice
                if ((rowdata.perm.includes("DATASET_DELETE")) &&
                    (rowdata.removed == 0)) {
                        return false;
                    } else { return true; }
            } else if (menu.name == "Metadata..") {
                // modify metadata
                if ((rowdata.perm.includes("DATASET_CHANGE")) &&
                    (rowdata.removed == 0)) {
                        return false;
                    } else { return true; }
            } else if (menu.name == "Permissions..") {
                // modify permissions
                return false;                
            } else if (menu.name == "Remove..") {
                // remove dataset
                if ((rowdata.perm.includes("DATASET_DELETE")) &&
                    (rowdata.removed == 0) &&
                    (rowdata.status == "CLOSED")) {                        
                        return false;
                    } else { return true; }
            } else if (menu.name == "Rerun..") {
                // rerun dataset store-task
                if ((rowdata.perm.includes("DATASET_RERUN")) &&
                    (rowdata.status == "FAILED")) {
                        return false;
                    } else { return true; }
            } else { return true; }
        } else if (field.name == "Retrieve") { 
            // retrieve data
            if ((rowdata.removed <= 0) &&
                (rowdata.status == "CLOSED") &&
                (rowdata.perm.includes("DATASET_READ"))) {
                    return false;                    
                } else { return true; }
        } else if (field.name == "View") {            
            if (menu.name == "Log") {
                // log is the menu choice
                if (rowdata.perm.includes("DATASET_READ")) { return false; } else { return true; }
            } else if (menu.name == "Metadata") {
                // metadata is the menu choice
                if (rowdata.perm.includes('DATASET_METADATA_READ')) { return false; } else { return true; }
            } else { return true; }    
        } else { return true; } // default to disabling unknown fields
    }

    // check if a status image for a data field is to be visible or not?
    const handleImageVisible = (field,imagepos,rowdata) => {
        // first establish which image we are checking visible for
        if (imagepos == 0) {
            // padlock_open 
            if (rowdata.status === "OPEN") {
                return true;
            } else { return false; }            
        } else if (imagepos == 1) {    
            // padlock_closed 
            if (rowdata.status !== "OPEN") {
                return true;
            } else { return false; }
        } else if (imagepos == 2) {
            // storage removed
            if (rowdata.status !== "OPEN") {
                if (rowdata.removed > 0) {
                    return true;
                } else { return false; }
            }
        } else if (imagepos == 3) {
            // storage exists
            if (rowdata.status !== "OPEN") {
                if (rowdata.removed === 0) {
                    return true;
                } else { return false; }
            }
        } else if (imagepos == 4) {
            // manual dataset
            if (rowdata.type == "MANUAL") {
                return true;
            } else { return false; }            
        } else if (imagepos == 5) {
            // manual dataset
            if ((rowdata.type == "AUTOMATED") ||
                (rowdata.type == "AUTOMATIC")) {
                return true;
            } else { return false; }                
        } else { return false; }
    }

    // check if a status icon for a data field is to be visible or not?
    const handleIconVisible = (field,imagepos,rowdata) => {
        // first establish which icon we are checking visible for
        if (imagepos == 0) {
            // padlock_open 
            if (rowdata.status === "OPEN") {
                return true;
            } else { return false; }            
        } else if (imagepos == 1) {    
            // padlock_closed 
            if (rowdata.status !== "OPEN") {
                return true;
            } else { return false; }
        } else if (imagepos == 2) {
            // storage removed
            if (rowdata.status !== "OPEN") {
                if (rowdata.removed > 0) {
                    return true;
                } else { return false; }
            }
        } else if (imagepos == 3) {
            // storage exists
            if (rowdata.status !== "OPEN") {
                if (rowdata.removed === 0) {
                    return true;
                } else { return false; }
            }
        } else if (imagepos == 4) {
            // manual dataset
            if (rowdata.type == "MANUAL") {
                return true;
            } else { return false; }            
        } else if (imagepos == 5) {
            // automated dataset
            if ((rowdata.type == "AUTOMATED") ||
                (rowdata.type == "AUTOMATIC")) {
                return true;
            } else { return false; }                
        } else { return false; }
    }

    // field - header definition for the row in question
    // rowdata - data structure of the row in question
    const handleModify = (field,menu,rowdata) => {
        iddata=rowdata;
        if (menu.name == "Metadata..") {
            id=rowdata.id;
            metadatafinished=false;
            showMetadata=true;            
        } else if (menu.name == "Expire Date..") {
            id=rowdata.id;           
            showExpire=true;
        } else if (menu.name == "Permissions..") {
            id=rowdata.id;            
            showPermissions=true;
        } else if (menu.name == "Close..") {
            id=rowdata.id;
            showClose=true;
        } else if (menu.name == "Remove..") {
            id=rowdata.id;
            showRemove=true;
        }
    }

    // field - header definition for the row in question
    // rowdata - data structure of the row in question
    const handleRetrieve = (field,menu,rowdata) => {
        iddata=rowdata;
        // we also need to save the interface entity id to iddata
        iddata.interface=menu.interface;        
        id=rowdata.id;      
        showRetrieve=true;
    }

    // field - header definition for the row in question
    // rowdata - data structure of the row in question
    const handleView = (field,menu,rowdata) => {
        iddata=rowdata;
        if (menu.name == "Metadata") {
            id=rowdata.id;
            metadatafinished=false;
            showMetadataRO=true;            
        } else if (menu.name == "Log") {
            id=rowdata.id;            
            showLog=true;
        }
    }   
    
    // close metadata modal
    const closeMetadata = () => {
        showMetadata=false;
        showMetadataRO=false;
        metadatafinished=true;
    }

    // close the expire modal
    const closeExpire = () => {
        showExpire=false;        
    }

    const closePermissions = () => {
        showPermissions=false;
    }

    const closeClose = () => {
        showClose=false;
    }

    const closeRemove = () => {
        showRemove=false;
    }

    const closeRetrieve = () => {
        showRetrieve=false;
    }

    const closeLog = () => {
        showLog=false;
    }

    const closeAck = () => {
        showAck=false;
    }
        
    // init tasks, like defining the tables being used
    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // set disabled
        disabled = CFG["www.maintenance"]||false;
        // check if we have a route in cookie
        if (/^.+$/.test(getCookieValue(CFG["www.cookiename"],"route"))) {
            // we have route data in the cookie, remove it because its already in routestr
            setCookieValue(CFG["www.cookiename"],"route","",CFG["www.domain"],CFG["www.cookie.timeout"]);
            setCookieValue(CFG["www.cookiename"],"routeparams","",CFG["www.domain"],CFG["www.cookie.timeout"]);
        }
        // fetch searchstruct from cookie
        let structstr;
        if ((routestr === 'manage') && (routepars['sqlstruct'] !== undefined)) {
            // structstr has been provided as parameter
            structstr = routepars['sqlstruct'];
        } else {
            // there is no structstr , get it from cookies if at all
            structstr = getCookieValue(CFG["www.cookiename"],"sqlstruct");
        }

        // ensure we have a valid value of some kind        
        if ((structstr != undefined) && (structstr != "")) {
            let structobj;
            try {
                // attempt to json decode the sqlstruct value
                structobj = JSON.parse(structstr);
                // check that start-object of sqlstruct is an array, if not fail
                // by setting the "empty" structure
                if (!Array.isArray(structobj)) { structobj = sstructtmpl; }
            } catch (error) {
                // something failed in the sqlstruct json decoding of the sqlstruct - set a blank one in the app                
                structobj = sstructtmpl;
            }   
            // set the search struct
            searchstruct = (typeof structobj == "object" ? structobj : searchstruct);         
        } 
        // fetch quicksearch string from cookie
        quicksearch = getCookieValue(CFG["www.cookiename"],"quicksearch");
        // get page count, if any
        let pcount=getCookieValue(CFG["www.cookiename"],"pagecount");
        count = string2Number(pcount,count);        

        // get if removed datasets are to be included or not?
        let removed=getCookieValue(CFG["www.cookiename"],"removed");
        removed = (removed == "false" ? "false" : "true");
        inclrm = string2Boolean(removed,inclrm);
        
        // get if we sort ascending or descending
        sortdir = getCookieValue(CFG["www.cookiename"],"sortdir");
        sortdir = (sortdir == "ASC" ? "ASC" : "DESC");
        sortdirint = (sortdir == "ASC" ? 1 : -1);

        // get what we sort by
        sortby = getCookieValue(CFG["www.cookiename"],"sortby");
        sortby = (sortby == "" || sortby == undefined ? MD["entity_id"] : sortby);

        // get the way we sort
        sorttype = getCookieValue(CFG["www.cookiename"],"sorttype");
        sorttype = (sorttype == "" || sorttype == undefined ? 1 : string2Number(sorttype));

        // attempt an authentication automatically
        // and thereby check our credentials
        // we will be redirected to login-page if it fails
		call_aurora("doAuth",undefined);
        // define headers
        headers.orderby="id";
        headers.oddeven=true;
        headers.oddcolor="";
        headers.evencolor="";
        headers.fields=[
            { name: "Dataset ID", dataname: "id", visible: true },
            { name: "Group", dataname: "parentname", visible: true },
            { name: "Created", dataname: "created", dataconverter: unixtime2ISO, visible: true },
            { name: "Creator", dataname: "creator", visible: true },
            { name: "Description", dataname: "description", visible: true },
            { name: "Expire", dataname: "expire", dataconverter: unixtime2ISO, visible: true },
            { name: "Status", dataname: "status", visible: true, 
                image: {
                    0:  { src: CFG["www.base"]+"/media/SOMEFILE.png",
                          alt: "Dataset WHATEVER",
                        },
                },    
                icon: {
                    0:  {
                            name: "lock open",
                            description: "Dataset Open",
                            fill: "#FF8040",
                        },
                    1:  {
                            name: "lock closed",
                            description: "Dataset Closed",
                            fill: "#666",
                        },     
                    2:  {
                            name: "folder off",
                            description: "Dataset Data Removed",
                            fill: "#666",
                    },     
                    3:  {
                            name: "folder",
                            description: "Dataset Data Present",
                            fill: "#666",
                    },
                    4:  {
                            name: "manual",
                            description: "Manual Dataset",
                            fill: "#666",
                    },     
                    5:  {
                            name: "automated",
                            description: "Automated Dataset",
                            fill: "#666",
                    },     
                },
                iconvisible: handleIconVisible,
                imagevisible: () => { return false; },
            },
            { name: "Modify", menu: [ 
                                      { name: String.fromCharCode(8801), dataname: "id", action: undefined, disabled: handleDisabled, hidden: true, selected: true },
                                      { name: "Close..", dataname: "id", action: handleModify, disabled: handleDisabled },
                                      { name: "Expire Date..", dataname: "id", action: handleModify, disabled: handleDisabled },
                                      { name: "Metadata..", dataname: "id", action: handleModify, disabled: handleDisabled },
                                      { name: "Permissions..", dataname: "id", action: handleModify, disabled: handleDisabled },
                                      { name: "Remove..", dataname: "id", action: handleModify, disabled: handleDisabled },
//                                      { name: "Rerun..", dataname: "id", action: handleModify, disabled: handleDisabled },
                                    ], visible: true },
            { name: "Retrieve", visible: true },
            { name: "View", menu: [ 
                                    { name: String.fromCharCode(8801), dataname: "id", action: undefined, disabled: handleDisabled, hidden: true, selected: true },
                                    { name: "Log", dataname: "id", action: handleView, disabled: handleDisabled },
                                    { name: "Metadata", dataname: "id", action: handleView, disabled: handleDisabled },
                                  ], visible: true },
        ];       

        // get interfaces
        getInterfaces();
        // init cache and get the data for the first screen
        cache = new AuroraDatasetCache(CFG["dataset.cache.size"],sortdir,sortby,sorttype);    
        // copy the structure
        let search=JSON.parse(JSON.stringify(searchstruct));              
        // clean away filters
        removeFilters(search); 
        cache.searchStruct(search); 
        // check route                
        let rclear = false;
        if (routestr == "close") {
            id = routepars["id"] || 0;
            showClose = true;                        
            rclear = true;
        } else if (routestr == "expire") {
            id = routepars["id"] || 0;
            showExpire = true;                        
            rclear = true;
        } else if (routestr == "metadata") {    
            id = routepars["id"] || 0;
            showMetadata = true;
            metadatafinished = false;
            rclear = true;
        } else if (routestr == "permissions") {
            id = routepars["id"] || 0;
            showPermissions = true;
            rclear = true;
        } else if (routestr == "remove") {
            id = routepars["id"] || 0;
            showRemove = true;
            rclear = true;
        } else if (routestr == "retrieve") {
            id = routepars["id"] || 0;
            iddata={};
            iddata.interface = routepars["ifid"] || 0;
            showRetrieve = true;
            rclear = true;
        } else if (routestr == "log") {    
            id = routepars["id"] || 0;
            showLog = true;            
            rclear = true;
        } else if (routestr == "ack") {
            id = routepars["id"] || 0;
            rid = routepars["rid"] || "";
            showAck = true;
            rclear = true;
        }
        if (rclear) {
            // reset route since we have routed already
            // we ignore the parameter list because it is not used without a route
            route.set("");
        } else {
            // we did not do any routing, so we execute the search
            searching=true;
            search=doSearch();
        }
	});
    
    // get the interfaces
    async function getInterfaces () {
        // get interfaces that exists for datasets
        let params={};
        let result=await call_aurora("enumInterfaces",params);

        if (result.err == 0) {
            // rest-call was a success
            let interf=result.interfaces;
            // add interfaces to header-definition
            if (Object.keys(interf).length > 0) { 
                headers.fields[8].menu=[]; 
                // add the hidden option
                headers.fields[8].menu.push({ name: String.fromCharCode(8801), dataname: "id", action: undefined, 
                                              disabled: handleDisabled, hidden: true, selected: true });
            }
            for (let key in interf) {
                // add interface to headers   
                let i={};
                i.name=interf[key];
                i.interface=key;
                i.action=handleRetrieve;
                i.disabled=handleDisabled;
                headers.fields[8].menu.push(i);
            }; 
            return 1;
        } else { return 0; }
    }

    // update searchstruct with removed setting
    const updateRemoved = (ev) => {        
        let value;
        if ((ev != undefined) && (ev.target != undefined) && (ev.target.value != undefined)) {
            value = ev.target.value;
            inclrm=value; 
        } else { value = inclrm; }
        // check if include/exclude entry is there already and its/theirs position
        let foundincl = -1;        
        let foundexcl = -1;
        for (let i=0; i < searchstruct.length; i++) {
            if ((!Array.isArray(searchstruct[i])) && (typeof searchstruct[i] == "object") && 
                (Object.keys(searchstruct[i]).includes(MD["dataset_removed"])) && 
                (Object.keys(searchstruct[i][MD["dataset_removed"]]).includes(">=")) && (searchstruct[i][MD["dataset_removed"]][">="] == 0)) {
                // the necessary entry is there already    
                // save index
                foundincl = i;   
                if (foundexcl > -1) { break; }
            } else if ((!Array.isArray(searchstruct[i])) && (typeof searchstruct[i] == "object") && 
                (Object.keys(searchstruct[i]).includes(MD["dataset_removed"])) && 
                (Object.keys(searchstruct[i][MD["dataset_removed"]]).includes("=")) && (searchstruct[i][MD["dataset_removed"]]["="] == 0)) {
                // the necessary entry is there already    
                // save index
                foundexcl = i;               
                if (foundincl > -1) { break; }
            }                                                
        }      
        // are we to include the setting or not?        
        if (String(value) === "true") {
            // it is true, 
            if (foundexcl > -1) {
                // not supposed to be here - remove it
                searchstruct.splice(foundexcl,1);
                optupdated=true;
            }
            if (foundincl == -1) {
                // we did not find the entry - add it
                let rm = {};
                rm[MD["dataset_removed"]]={ ">=": 0 };
                // add it to the list
                searchstruct.push(rm);
                optupdated=true;
            }
            // signal update to the SQLStructEditor
            update++;                      
        } else {
            // removed setting is not supposed to be there, remove it if it is
            if (foundincl > -1) {
                // include removed datasets are not to be here
                searchstruct.splice(foundincl,1);
                optupdated=true;
            }
            if (foundexcl == -1) {
                // we did not find the entry - add it
                let rm = {};
                rm[MD["dataset_removed"]]={ "=": 0 };
                // add it to the list
                searchstruct.push(rm);                
                optupdated=true;
            }
            // signal update to the SQLStructEditor
            update++;                
        }                
    }

    const updateSortby = (ev) => {  
        if ((ev != undefined) && (ev.target != undefined) && (ev.target.value != undefined)) {
            sortby = ev.target.value;   
            sorttype = 0;
            if (sortby == MD["entity_id"]) { sorttype = 1; headers.orderby="id"; }
            else if (sortby == MD["dataset_expire"]) { sorttype = 1; headers.orderby="expire"; }
            else if (sortby == MD["entity_parentname"]) { headers.orderby="parentname"; }
            else if (sortby == MD["dataset_created"]) { headers.orderby="created"; }
            else if (sortby == MD["dc_creator"]) { headers.orderby="creator"; }
            else if (sortby == MD["dc_description"]) { headers.orderby="description"; }
        }        
    }

    const updateSortDir = (ev) => {                
        if ((ev != undefined) && (ev.target != undefined) && (ev.target.value != undefined)) {
            sortdir = ev.target.value;
            sortdirint = (sortdir == "ASC" ? 1 : -1);
        }
    }

    const sortHandler = (field, dir) => {
        let o = {};
        o.target = {};
        o.target.value = "";
        // set the correct sortby value based upon field dataname
        if (field == "id") { o.target.value = MD["entity_id"]; }
        if (field == "expire") { o.target.value = MD["dataset_expire"]; }
        if (field == "parentname") { o.target.value = MD["entity_parentname"]; }
        if (field == "created") { o.target.value = MD["dataset_created"]; }
        if (field == "creator") { o.target.value = MD["dc_creator"]; }
        if (field == "description") { o.target.value = MD["dc_description"]; }        

        // only do soet changes if the field has been set to a valid value
        if (o.target.value != "") {
            // check if we have a change of field to sort by
            // if so, always start sorting ascending (toggled further down)
            if (field != headers.orderby) { dir = -1;  }
            // fix direction, toggle
            dir = dir * -1;
            sortdir = (dir == 1 ? "ASC" : "DESC");
            sortdirint = dir;
            
            // update sortby
            updateSortby (o);

            // do a search
            optupdated = true;
            searching=true; 
            cache.searchStruct(sstructtmpl);
            offset=1;
            doSearch();
        }
    }

    const convertQuickSearch = () => {
        if (quicksearch != "") {
            // clear search structure
            clearStruct();
            // add a OR-group
            searchstruct.push(["OR"]);          
            // fill or-group with searchstructures for each field using the quicksearch value
            let a={};
            a[MD["entity_id"]]={"=": "*"+quicksearch+"*" };
            let b={};
            b[MD["dataset_expire"]]={ "=": quicksearch };
            b["#"+MD["dataset_expire"]]=1; // filter from ISO8601 to unixtime
            let c={};
            c[MD["entity_parentname"]]={"=": "*"+quicksearch+"*" };
            let d={};
            d[MD["dc_date"]]={"=": "*"+quicksearch+"*" };
            let e={};
            e[MD["dc_creator"]]={"=": "*"+quicksearch+"*" };
            let f={};
            f[MD["dc_description"]]={"=": "*"+quicksearch+"*" };

            searchstruct[2].push(a);
            searchstruct[2].push(b);
            searchstruct[2].push(c);
            searchstruct[2].push(d);
            searchstruct[2].push(e);
            searchstruct[2].push(f);                          
        } else {
            // quicksearch input is blank, so we use what already exists  
            // this is in effect advanced search          
        }

        // update search
        optupdated=true;
        searching=true;
        cache.searchStruct(sstructtmpl);
        offset=1;
        doSearch();
    };

    // update cookie with the latest 
    // search settings
    const updateCookie = () => {        
        // save new version of search structure to cookie
        setCookieValue(CFG["www.cookiename"],"sqlstruct",JSON.stringify(searchstruct),CFG["www.domain"],CFG["www.cookie.timeout"],"/");
        // save quicksearch value        
        setCookieValue(CFG["www.cookiename"],"quicksearch",quicksearch,CFG["www.domain"],CFG["www.cookie.timeout"],"/");
        // save page-count
        setCookieValue(CFG["www.cookiename"],"pagecount",count,CFG["www.domain"],CFG["www.cookie.timeout"],"/");  
        // save removed
        setCookieValue(CFG["www.cookiename"],"removed",inclrm,CFG["www.domain"],CFG["www.cookie.timeout"],"/");   
        // save sortdir
        setCookieValue(CFG["www.cookiename"],"sortdir",sortdir,CFG["www.domain"],CFG["www.cookie.timeout"],"/");   
        // save sortby
        setCookieValue(CFG["www.cookiename"],"sortby",sortby,CFG["www.domain"],CFG["www.cookie.timeout"],"/");   
        // save sorttype
        setCookieValue(CFG["www.cookiename"],"sorttype",sorttype,CFG["www.domain"],CFG["www.cookie.timeout"],"/");   
    }
   
    // clean search structure of filters
    const removeFilters = (s) => {
        for (let key in s) {
            if (/^\#(.*)$/.test(key)) {
                // this is a filter - run it
                let match = key.match(/^\#(.*)$/);
                let orgkey=match[1];
                if (typeof s[orgkey] == "object") {
                    // this is an object with sub-keys that can be converted
                    for (let subkey in s[orgkey]) {
                        if (s[key] == 1) {
                            // ISO8601      
                            s[orgkey][subkey] = ISO2Unixtime(s[orgkey][subkey]);
                        } else if (s[key] == 2) {
                            // BYTE DENOM
                            s[orgkey][subkey] = SI2Int(s[orgkey][subkey]);
                        }
                    }
                }    
                // then remove the filter key
                delete s[key];
            } else {
                // check if we need to recurse into structure
                if (typeof s[key] == "object") {
                    // this is a sub-key object - recurse into it
                    removeFilters(s[key]);
                }
            }
        }
    }

    // execute the search
    async function doSearch () {               
        // update searchstruct with removed setting
        updateRemoved();
        // update cookie
        updateCookie();
        // check if options change that require REST-server call has happened or not?
        if (optupdated) {            
            // options change that require a REST-call has happened                        
            optupdated=false;
            // clean searchstruct, first copy it
            let search = JSON.parse(JSON.stringify(searchstruct));
            // clean away all filter keys
            removeFilters(search);
            searching=true;
            offset=1;
            // only update order and sortby if they have changed
            if (cache.order() != sortdir) { cache.order(sortdir); }
            if (cache.sortby() != sortby) { cache.sortby(sortby); cache.sorttype(sorttype); }
            // this triggers a complete REST-call
            cache.searchStruct(search);
        }
        // get datasets
        let result=await cache.page(offset,count);

        await result;

        // check if it was a success or not
        if (result.err == 0) {
            // rest-call was a success
            data=result.datasets;
            // save the total
            total=result.total;
            // calculate search speed in seconds
            speed=result.delivered-result.received;
            searching=false;
            return 1;
        } else { searching=false; return 0; }
    }        

    const navigate = (dir,absolute=false) => {
        let search=true;
        if (dir == -1) {
            // go back
            if ((absolute) && (offset != 1)) { offset=1; }
            else if (offset - count < 1) { offset=1; search=false; }
            else { offset = offset - count; }
        } else if (dir == 1) {
            // go forward
            if ((absolute) && (offset != total)) { 
                // calculate number of pages
                let pages = Math.ceil(total/count);
                // go to last page of all pages
                offset = ((pages-1) * count) + 1;                
            }
            else if ((offset + count) > total) { search=false; } 
            else { offset = offset + count; }
        }
        // execute a new search with the REST-server
        if (search) {
            searching=true;
            doSearch();
        }    
    }

    // reset/clear search structure
    const clearStruct = () => {
        // reset search-structure
        searchstruct=["AND"];
        // update include/exclude setting in searchstruct
        updateRemoved("./settings.yaml",);
    };

    const checkEnter = (ev,func) => {
        if ((ev != undefined) && (ev.keyCode == 13)) {   
            // enter was pressed - launch function if it is defined
            if (func != undefined) { func(); }
        }
    }   
</script>

{#if !disabled}
    {#if search != undefined}
        {#if !searching}
            <div class="ui_search_status">Page {Math.floor((offset-1)/count) + 1}/{Math.ceil(total/count)} ({total} datasets) ({speed.toFixed(2)} sec(s))</div>
            <div class="ui_center">                    
                <div class="ui_row ui_margin_top ui_input">                        
                    <input                             
                        type="text" 
                        bind:value={quicksearch} 
                        on:keypress={(ev) => { checkEnter(ev,convertQuickSearch); }} 
                        size="60" 
                        maxlength="1024" 
                    />                        
                </div>
                <div class="ui_row ui_margin_top">
                    <button class="ui_button" on:click={() => { convertQuickSearch(); }}>Search</button>
                    <button class="ui_button" on:click={() => { quicksearch=""; clearStruct(); }}>Clear</button>
                </div>
                <!-- show the expand/collapse icons for the advanced features such as sqlstruct -->
                <!-- svelte-ignore a11y-click-events-have-key-events -->
                <div class="ui_row ui_margin_top" on:click={() => { showsearchbar = !showsearchbar }}>
                    {#if showsearchbar}
                        <Icon name="unfoldless" fill="#555" size="40" />
                    {:else}
                        <Icon name="unfoldmore" fill="#555" size="40" />
                    {/if}
                </div>
                <!-- show rows/page and if to include removed datasets options -->
                {#if showsearchbar}                        
                    <!-- show the quick search input -->                        
                    <div class="ui_row ui_margin_top">                            
                        <!-- ensure that a new REST-call for search is performed if results/page has changed -->
                        Results/page&nbsp;
                        <input class="ui_input" type="number" min=1 max={cache.size}
                            on:change={() => { optupdated=true; }}
                            bind:value={count}
                        >
                        Removed datasets&nbsp;
                        <select class="ui_input" on:change={(ev) => { optupdated=true; updateRemoved(ev); }}>
                            <option value={true} selected={(String(inclrm) == "true" ? true : false)}>Include</option>
                            <option value={false} selected={(String(inclrm)  == "true" ? false : true)}>Exclude</option>
                        </select>

                        Sort by&nbsp;
                        <select class="ui_input" on:change={(ev) => { optupdated=true; updateSortby(ev); }}>
                            <option value={MD["entity_id"]} selected={(String(sortby) == MD["entity_id"] ? true : false)}>Dataset ID</option>
                            <option value={MD["entity_parentname"]} selected={(String(sortby)  == MD["entity_parentname"] ? true : false)}>Group</option>
                            <option value={MD["dataset_created"]} selected={(String(sortby)  == MD["dataset_created"] ? true : false)}>Created</option>
                            <option value={MD["dc_creator"]} selected={(String(sortby)  == MD["dc_creator"] ? true : false)}>Creator</option>
                            <option value={MD["dc_description"]} selected={(String(sortby)  == MD["dc_description"] ? true : false)}>Description</option>
                            <option value={MD["dataset_expire"]} selected={(String(sortby)  == MD["dataset_expire"] ? true : false)}>Expire</option>
                        </select>

                        Sort Direction&nbsp;
                        <select class="ui_input" on:change={(ev) => { optupdated=true; updateSortDir(ev); }}>
                            <option value="ASC" selected={(String(sortdir) == "ASC" ? true : false)}>Ascending</option>
                            <option value="DESC" selected={(String(sortdir)  == "DESC" ? true : false)}>Descending</option>
                        </select>

                    </div>                        
                {/if}
            </div>
            <!-- show the SQLStructEditor if expanded -->
            {#if showsearchbar}
                <div class="ui_center">
                    <SqlStructEditor sqlstruct={searchstruct} bind:update={update} />
                </div>
            {/if}                    
        {/if}
        {#await search}
            &nbsp;
        {:then result}
            {#if data != undefined && !searching}
                <!-- show navigation buttons -->
                <div class="ui_navigate">
                    <button class="ui_button" on:click={() => { navigate(-1)} }>&#60;&#61; Previous</button>
                    <button class="ui_button" on:click={() => { navigate(-1,true)} }>First</button>                    
                    <button class="ui_button" on:click={() => { navigate(1,true)} }>Last</button>
                    <button class="ui_button" on:click={() => { navigate(1)} }>Next &#61;&#62;</button>
                </div>
                <!-- show the dataset table itself -->
                <Table data={data} headers={headers} disabled={!metadatafinished} orderdirection={sortdirint} sorthandler={sortHandler} />

                <!-- show the navigation buttons again -->
                <div class="ui_navigate">
                    <button class="ui_button" on:click={() => { navigate(-1)} }>&#60;&#61; Previous</button>
                    <button class="ui_button" on:click={() => { navigate(-1,true)} }>First</button>                    
                    <button class="ui_button" on:click={() => { navigate(1,true)} }>Last</button>
                    <button class="ui_button" on:click={() => { navigate(1)} }>Next &#61;&#62;</button>
                </div>        
            {/if}
        {/await}
    {/if}    
    {#if searching}
        <Status message="Retrieving datasets..." type="processing" />     
    {/if}
    <!-- Modify -> Expire -->
    {#if showExpire}    
        <Modal width="80" height="90" border={false} closeHandle={() => { closeExpire() }}>            
            <Expire id={id} />
        </Modal>    
    {/if}
    <!-- Modify -> Metadata -->
    {#if showMetadata && !metadatafinished}
        <Modal width="80" height="90" border={false} closeHandle={() => { closeMetadata() }}>
            <MetadataEditor id={id} view={false} finishedHandle={() => { closeMetadata() }} bind:finished={metadatafinished} />
        </Modal>    
    {/if}
    <!-- Modify -> Permissions -->
    {#if showPermissions}
        <Modal width="80" height="90" border={false} closeHandle={() => { closePermissions() }}>
            <Permissions id={id} type="DATASET" />
        </Modal>    
    {/if}    
    <!-- View -> Metadata -->
    {#if showMetadataRO && !metadatafinished}
        <Modal width="80" height="90" border={false} closeHandle={() => { closeMetadata() }}>
            <MetadataEditor id={id} view={true} finishedHandle={() => { closeMetadata() }} bind:finished={metadatafinished} />
        </Modal>    
    {/if}
    {#if showClose}
        <Modal width="80" height="90" border={false} closeHandle={() => { closeClose() }}>
            <Close id={id} />
        </Modal>    
    {/if}
    {#if showRemove}
        <Modal width="80" height="90" border={false} closeHandle={() => { closeRemove() }}>
            <Remove id={id} />
        </Modal>    
    {/if}
    {#if showRetrieve}
        <Modal width="80" height="90" border={false} closeHandle={() => { closeRetrieve() }}>
            <Retrieve id={id} ifid={iddata["interface"]} />
        </Modal>    
    {/if}
    {#if showLog}
        <Modal width="80" height="90" border={false} closeHandle={() => { closeLog() }}>
            <Log id={id} />
        </Modal>    
    {/if}
    {#if showAck}
        <Modal width="80" height="90" border={false} closeHandle={() => { closeAck() }}>
            <Ack id={id} rid={rid} closeHandle={() => { closeAck() }} />
        </Modal>    
    {/if}
{:else}
   {window.location.href=CFG["www.base"]}
{/if}




    

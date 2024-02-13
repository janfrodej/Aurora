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
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="Log";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";
    import { call_aurora } from "./_aurora.js";
    import { unixtime2ISO } from "./_iso8601";
    import Table from "./Table.svelte";
    import Status from "./Status.svelte";
    import { onMount } from 'svelte';
    import { MD } from './_sysschema';
    import { int2SI } from "./_tools";


    let CFG={};
    let disabled=false;

    // some input/output variables
    export let id = 0;
    id=Number(id);
    export let loglevel = "INFORMATION";
    export let tag = false;

    // some promises
    let getdata;
    // some variables
    let md = {};
    let mdtable = {};
    let mdtabledata = {};
    let log = {}; // all of log data
    let logtable = {}; // definition og log table
    let logtabledata = {}; // processed log    
    let show = false;

    // some constants
    const loglevels = {
        "DEBUG": 0,
        "INFORMATION": 1,
        "WARNING": 2,
        "ERROR": 3,
        "FATAL": 4,
    };
    const selectlevels = [
        { id: "DEBUG", text: "DEBUG" },
        { id: "INFORMATION", text: "INFORMATION" },
        { id: "WARNING", text: "WARNING" },
        { id: "ERROR", text: "ERROR" },
        { id: "FATAL", text: "FATAL" },
    ]
    const radiooptions = [
        { value: true, label: "Show Tag" },
        { value: false, label: "Hide Tag" },
    ];

    // on finished rendering
    onMount(async () => {        
      // fetch configuration and wait
      CFG = await getConfig();
      // set disabled
      disabled = CFG["www.maintenance"]||false;
      // attempt an authentication automatically
      // and thereby check our credentials
      // we will be redirected to login-page if it fails
	  call_aurora("doAuth",undefined);
      // get the data for the first screen
      updateData();
	});

    // set the retrieved metadata in md variable of component
    const setMetadata = (metadata) => {
        // do not show anything if we failed to retrieve metadata for an entity
        if (metadata["metadata"] == undefined) { return ""; }    
        md = metadata["metadata"];
        // put data into mdtabledata
        let i = 1;
        mdtabledata[i]={};
        mdtabledata[i]["attr"] = "Created";
        mdtabledata[i]["value"] = unixtime2ISO(md[MD["dataset_created"]]||0); 
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Expire Date";
        mdtabledata[i]["value"]=unixtime2ISO(md[MD["dataset_expire"]]||0);
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Creator";
        mdtabledata[i]["value"]=md[".Creator"]||"N/A";
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Computer";
        mdtabledata[i]["value"]=md[MD["dataset_computername"]]||"N/A";
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Dataset Type";
        mdtabledata[i]["value"]=md[MD["dataset_type"]]||"N/A";
        i++;
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Group";
        mdtabledata[i]["value"]=md[MD["entity_parentname"]]||"N/A";
        i++;
        let size = md[MD["dataset_size"]];
        mdtabledata[i]={};
        mdtabledata[i]["attr"]="Dataset Size";
        mdtabledata[i]["value"]=(md[MD["dataset_status"]] == "CLOSED" ? int2SI(size)+" ("+size+")" : "N/A");

        return "";
    };

    // save/set the resultant log from the REST-call
    const setLog = (result) => {
        // do not show anything if we failed to retrieve log for an entity
        if (result["log"] == undefined) { return ""; }    
        log = result.log;
        // refresh log structure data
        processLog();
        return "";
    };

    // process the retrieved log and prepare it for viewing
    const processLog = () => {    
        show = false;  
        // put data in place
        logtabledata={};        
        let i=0;      
        for (let no in log) {
            // only include log entry if at current loglevel or higher
            if (loglevels[log[no].loglevel] >= loglevels[loglevel]) {
                i++;
                logtabledata[i] = {};
                logtabledata[i]["time"]=unixtime2ISO(log[no].time || 0);
                logtabledata[i]["loglevel"]=log[no].loglevel || "DEBUG";
                logtabledata[i]["tag"]=log[no].tag || "";
                logtabledata[i]["message"]=log[no].message || "";
            }
        }
        // signal that we are ready to show the data
        show = true;     
    }

    const defineLog = () => {
        logtable={};
        logtable.oddeven=true;    
        logtable.orderby="time";
        logtable.fields=[
            { name: "Time", dataname: "time", visible: true },
            { name: "Loglevel", dataname: "loglevel", visible: true },            
        ];
        // check if log tag is to be included or not?
        if (tag) {
            // log tag is to be included
            logtable.fields.push ({ name: "Tag", dataname: "tag", visible: true });
        } 
        logtable.fields.push ({ name: "Message", dataname: "message", visible: true });
        return "";
    };

    // define close table
    const defineTable = () => {
        // define the component table       
        mdtable.oddeven=true;    
        mdtable.orderby="attr";
        mdtable.fields=[
            { name: "Attribute", dataname: "attr", visible: true },
            { name: "Value", dataname: "value", visible: true },            
        ];
    };

    // get all metadata for dataset
    async function getData() {
        show = false;
        // define metadata table look
        defineTable();
        // define log table look
        defineLog();
              
        // get dataset metadata
        let params={};
        // set dataset id
        params["id"] = id;
        let getmd = await call_aurora("getDatasetSystemAndMetadata",params);

        await getmd;

        if (getmd.err === 0) { setMetadata(getmd); }

        // get dataset log
        // we use local getlogdata to differntiate from global getlog
        params={};
        params["id"] = id;
        params["loglevel"] = loglevel;
        let getlog=await call_aurora("getDatasetLog",params);

        await getlog;

        if (getlog.err === 0) { setLog(getlog); }
        
        if ((getmd.err === 0) &&  (getlog.err === 0)) { return 1; } else { return 0; }
    }

    async function updateData() {
        getdata=undefined;
        getdata=getData();
    }
</script>

<!-- Rendering -->
{#if !disabled}
    {#if getdata != undefined}
        {#await getdata}
            <Status message="Retrieving dataset metadata and log..." type="processing" />       
        {/await}
    {/if}
    {#if show}        
        <div class="ui_center">      
            <!-- header-data -->
            <div class="ui_title">Log for Dataset</div>
            <div class="ui_output">{id}</div>
            <div class="ui_label">Description</div>
            <div class="ui_output">{md[".Description"]}</div>    
            <div class="ui_label">Status</div>
            {#if md[MD["dataset_status"]] === "OPEN"}
                <div class="status_open">{md[MD["dataset_status"]]}</div>
            {:else if md[MD["dataset_status"]] === "CLOSED"}
                <div class="status_closed">{md[MD["dataset_status"]]}</div>
            {:else if md[MD["dataset_status"]] === "DELETED" }
                <div class="status_deleted">{md[MD["dataset_status"]]}</div>
            {:else}
                <div class="ui_output">{md[MD["dataset_status"]]}></div>
            {/if}
            <!-- loglevel option -->
            <div class="ui_label">Loglevel</div>
            <select bind:value={loglevel} on:change={() => { updateData(); } }>
                {#each selectlevels as level}
                    <option value={level.id}>{level.text}</option>
                {/each}
            </select>
            <!-- tag option -->            
            <label><input type="radio" name="showtag" value={true} bind:group={tag} selected={tag} on:change={() => { defineLog(); } } />Show Tag</label>
            <label><input type="radio" name="showtag" value={false} bind:group={tag} selected={!tag} on:change={() => { defineLog(); } } />Hide Tag</label>

            <!-- Refresh button to allow updating log entries from REST-server -->
            <button class="ui_button ui_margin_top" on:click={() => { updateData() }}>Refresh</button>
            <!-- show dataset metadata -->
            <Table data={mdtabledata} headers={mdtable} orderdirection={0} />
            <!-- show dataset log entries, no-sorting -->
            <Table data={logtabledata} headers={logtable} orderdirection={0} />
            <!-- Refresh button to allow updating log entries from REST-server -->
            <button class="ui_button ui_margin_top" on:click={() => { updateData() }}>Refresh</button>
        </div>
    {/if}
{/if}

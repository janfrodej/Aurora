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
    let compname="Expire";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { onMount } from 'svelte';
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";
    import { unixtime2ISO } from "./_iso8601";
    import { sendStatusMessage } from './_tools';
    import Table from "./Table.svelte";
    import Status from "./Status.svelte";
    import CircularDateTimeSlider from './CircularDateTimeSlider.svelte';

    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0;
    id=Number(id);

    // some promises
    let getmd;
    let expireds;
    // some variables
    let md = {};   
    let expiretable = {};
    let expiredata = {};
    let expiredatetime;
    let show = false;    
    
    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
    });  
    
    // get a datasets metadata
    // this also includes its expire policy
    async function getDatasetMetadata () {
        show=false;
        expiredatetime=0;
        let params={};
        params["id"]=id;
        // get system- and non-system metadata
        let result=await call_aurora("getDatasetSystemAndMetadata",params);
        // get dataset expire policy in effect
        let expres=await call_aurora("getDatasetExpirePolicy",params);

        if ((result.err === 0) && (expres.err === 0)) {
            // rest-call was a success
            md=result.metadata;  
            expiredatetime=md["system.dataset.time.expire"];
            let extendmax;
            let extendlimit;            
            if (md["system.dataset.status"] === "OPEN") {
                extendmax=expres["expirepolicy"]["open"]["extendmax"];
                extendlimit=expres["expirepolicy"]["open"]["extendlimit"];
            } else {
                extendmax=expres["expirepolicy"]["close"]["extendmax"];
                extendlimit=expres["expirepolicy"]["close"]["extendlimit"];
            }
            let extendmaxdays=Math.floor(extendmax/86400);
            let extendlimitdays=Math.floor(extendlimit/86400);
            let i=1;
            expiredata[i]={};
            expiredata[i]["attr"]="Created";
            expiredata[i]["value"]=unixtime2ISO(md["system.dataset.time.created"]);            
            if (md["system.dataset.status"] === "CLOSED") {
                i++;
                expiredata[i]={};
                expiredata[i]["attr"]="Closed";
                expiredata[i]["value"]=unixtime2ISO(md["system.dataset.time.closed"]);
            }
            i++;
            expiredata[i]={};
            expiredata[i]["attr"]="Expire Date";
            expiredata[i]["value"]=unixtime2ISO(md["system.dataset.time.expire"]);
            i++;
            expiredata[i]={};
            expiredata[i]["attr"]="Maximum Extension Increase";
            expiredata[i]["value"]=extendmaxdays + " day(s) (" + extendmax + " second(s))";
            i++;
            expiredata[i]={};
            expiredata[i]["attr"]="Absolute Extension Limit";
            expiredata[i]["value"]=extendlimitdays + " day(s) (" + extendlimit + " second(s))";
            show=true;
            return 1;
        } else {
            return 0;
        }
    }

    // attempt to update dataset expire date
    async function changeExpire () {       
       let params={};   
       params.id=id;
       params.expiredate=expiredatetime;
       let result=await call_aurora("changeDatasetExpireDate",params);       
       // check if it was a success or not
       if (result.err == 0) {         
          return 1;
       } else {           
          return 0;        
       }        
    }

    // define expire table
    const defineTable = () => {
        // define the expire-table
        //expiretable.orderby="id";
        expiretable.oddeven=true;    
        expiretable.orderby="attr";
        expiretable.fields=[
            { name: "Attribute", dataname: "attr", visible: true },
            { name: "Value", dataname: "value", visible: true },            
        ];
    };

    // get all metadata for dataset
    const getData = () => {
        defineTable();
        getmd=getDatasetMetadata();
    };

    // start retrieval of all necessary data
    getData();
</script>

<!-- Rendering -->
{#if !disabled}
    {#if getmd != undefined}
        {#await getmd}        
            <Status message="Retrieving dataset metadata..." type="processing" />     
        {:then result}
            &nbsp;
        {/await}
    {/if}
    {#if expireds != undefined}
        {#await expireds}
            <Status message="Updating dataset expire time..." type="processing" />                 
        {:then result}
            {#if result}
                {sendStatusMessage("Successfully changed dataset expire time...","INFO")}
            {/if}    
        {/await}
    {/if}
    {#if show && md["system.dataset.status"] != "DELETED"}
        <div class="ui_center">               
            <div class="ui_title">Change Expire Date</div>
            <div class="ui_label">Dataset {id}</div>
            <div class="ui_output">{md[".Description"]}</div>            
            {#if md["system.dataset.status"] === "OPEN"}
                <div class="status_open">{md["system.dataset.status"]}</div>
            {:else if md["system.dataset.status"] === "CLOSED"}
                <div class="status_closed">{md["system.dataset.status"]}</div>
            {:else if md["system.dataset.status"] === "DELETED" }
                <div class="status_deleted">{md["system.dataset.status"]}</div>
            {:else}
                <div class="ui_output">{md["system.dataset.status"]}></div>
            {/if}                        
            <Table data={expiredata} headers={expiretable} orderdirection={0} />            
            <CircularDateTimeSlider bind:datetime={expiredatetime} />            
            <button class="ui_button ui_margin_top" on:click={() => { expireds=changeExpire() }}>Change</button>            
        </div>
    {/if}    
    {#if md["system.dataset.status"] == "DELETED"} 
        <div class="ui_center ui_text_large">Dataset already removed. Unable to change its expire time.</div>
    {/if}    
{/if}

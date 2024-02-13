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
    let compname="Template";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";   
    import Status from "./Status.svelte";
    import { onMount } from 'svelte';
    import { PRESETS_SYSTEM } from './_sysschema';
    import { hash2SortedSelect, sortArray, sendStatusMessage } from "./_tools";

    let CFG={};
    let disabled=false;    

    // some input/output variables
    export let id = 0;
    id=Number(id);
    export let closeHandle;

    // some defs
    let presetlist=hash2SortedSelect(PRESETS_SYSTEM);

    // some promises
    let data;
    let updateent;
    
    // some variables    
    let show = false;
    let name = "";
    let updated = false;
    let templateflags = [];
    let addkeyvalue = "";

    let template = {};  
    let assignments = {};  

    // rerender trigger
    let rerender = 0;

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        data = getData();
    });      

    // call REST-server to set template 
    // constraints and name
    const setTemplate = () => {
        let params={};
        params["id"]=id;
        params["name"]=name;
        params["template"]=template;
        // reset all settings on template before adding these
        params["reset"]=1;
        updateent=call_aurora("setTemplate",params);
    };

    // get all data needed 
    async function getData () {    
        show = false;
       
        // enum template flags
        let params={};
        let getflags = await call_aurora("enumTemplateFlags",params);

        if (getflags.err == 0) {
            // get the flags
            templateflags = getflags.flags;
        }

        // get template constraints and name
        params={};
        // set dataset id
        params["id"] = id;
        let gettemp = await call_aurora("getTemplate",params);

        // was data retrieved successfully?
        if (gettemp.err == 0) {
            // save its name
            name = gettemp.name;

            // get template constraints
            template = gettemp.template;
        }

        // get template assignments
        let assigns={};
        params={};
        // set dataset id
        params["id"] = id;
        let getass = await call_aurora("getTemplateAssignments",params);

        // was data retrieved successfully?
        if (getass.err == 0) {
            // get types
            let types = getass.assignments.types;
            // go through each assignment and get its name
            for (let type in types) {            
                // create sub-hash
                assigns[type] = {};                
                for (let i=0; i < types[type].length; i++) { 
                    let tid=types[type][i];
                    // get the name of this entity
                    params={};
                    params["id"] = tid;
                    let getname = await call_aurora("getName",params);
                    if (getname.err == 0) {                        
                        // add entity to type
                        assigns[type][tid] = getname.name;
                    }
                }
            }
            // save assignments
            assignments = assigns;
        }

        if ((getflags.err == 0) && (getass.err == 0) && (gettemp.err == 0)) {
            // show data
            show = true;
            // return success 
            return 1;
        } else { return 0; }
    };

    // updates a hash's key name
    const updateKey = (key,newkey) => {
        if ((template[key] != undefined) && (template[newkey] == undefined)) {
            // save old object
            let o=template[key];
            // remove object from template
            delete template[key];
            // add new key-name
            // and refer to the old data
            template[newkey] = o;
        }
        return "";
    }

    const removeKey = (key) => {
        // delete the given key from the template hash
        delete template[key];
        rerender++;
    };

    const addKey = () => {
        // add key to template hash
        if ((template[addkeyvalue] == undefined) && (!/^\s*$/.test(addkeyvalue))) {
            // only attempt to add key if it doesnt exist already
            template[addkeyvalue]={
                min: 1,
                max: 0,
                regex: "[^\\000-\\037\\177]+",
                flags: [],
                comment: "",
                default: [""],
            };
            // rerender interface
            rerender++;
        }
    };

    // add a default value to a key
    const addDefault = (key,index) => {
        // add a default
        if (index != undefined) {
            // this is an array - insert after given index
            template[key].default.splice(index+1,0,"");
        } else {
            // its a string - convert to array
            let val=template[key].default;
            let arr=[];
            arr.push(val);
            // add a new empty default
            arr.push("");
            // set template default to the new array
            template[key].default=arr;
        }
        rerender++;
    };

    const removeDefault = (key,index) => {
        // remove entry in question
        template[key].default.splice(index,1); 
        rerender++;
    };

    const updateFlag = (key,flag,ev) => {
        let checked = ev.target.checked;
        let flags = (template[key].flags == undefined ? [] : template[key].flags);
        if (checked) {
            // if flag is not in template flags, add it
            if (!flags.includes(flag)) { flags.push(flag); }            
        } else {
            // if flag is in template flags, remove it
            if (flags.includes(flag)) { 
                let pos=flags.indexOf(flag);
                flags.splice(pos,1);                
            }
        }
        // set template flags to flags
        template[key].flags=flags;
    };

    const sendUpdated = () => {
        sendStatusMessage("Successfully updated template...","info");
        return "";
    }
</script>

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving template data..." type="processing" />
        {/await}
    {/if}
    {#if updateent != undefined}
        {#await updateent}
            <Status message="Updating template..." type="processing" />
        {:then result}
            {#if result.err == 0}
                {sendUpdated()}
            {/if}    
        {/await}
    {/if}
    {#if show}    
        <!-- show title and table with entity metadata -->
        <div class="ui_title ui_center">Edit Template</div>              
        <div class="ui_center">
            <div class="ui_output">Template Name</div>
            <div class="ui_input"><input type="text" bind:value={name} default={name}></div>
        </div>
        <!-- add key input -->
        <div class="ui_center">
            <div class="ui_output">Add key name</div>
        </div>
        <div class="ui_center_row">
            <div class="ui_input">
                <input type="text"
                    default={addkeyvalue}
                    bind:value={addkeyvalue} 
                    list="{compname}_preset_keylist_{myrand}" 
                    size={44} 
                    maxlength={1024} 
                    selected={true}
                >
            </div>
            <datalist id="{compname}_preset_keylist_{myrand}">
                <select size=8>               
                    {#each presetlist as item}
                        <option key={compname+"_"+myrand+"_presetkeylist_"+item.id} data-id={item.id} 
                            value={item.id}>{item.text}
                        </option>
                    {/each}
                </select>
            </datalist>
            <button class="ui_button" on:click={() => { addKey() }}>+</button>
        </div>        
        <!-- show buttons -->        
        <div class="ui_center_row">
            <button class="ui_button" on:click={() => { setTemplate() }}>Update</button>
            <button class="ui_button" on:click={() => { closeHandle() }}>Close</button>            
        </div>        
        <!-- show template constraints, if any -->
        {#key rerender}
            <div class="ui_margin_left">
                {#if Object.keys(assignments).length > 0}
                    <details>
                        <summary>Assignments</summary>
                        <ul>
                            {#each Object.keys(assignments) as type}
                                <li>
                                    as {type}
                                </li>
                                <ul>
                                    {#each Object.keys(assignments[type]) as id}
                                        <li>
                                            {assignments[type][id]} ({id})
                                        </li>
                                    {/each}
                                </ul>
                            {/each}
                        </ul>
                    </details>
                {/if}            
            </div>
            {#each sortArray(Object.keys(template)) as key,index}
                <div class="{(index % 2 == 0 ? "ui_container_light" : "ui_container_dark")}">
                    <div class="ui_right">
                        <button class="ui_button" on:click={() => { removeKey(key); }}>X</button>
                    </div>
                    <div class="ui_output">Key name</div>
                    <div class="ui_input">
                        <input type="text"
                            value={key} 
                            on:change={(ev) => { updateKey(key,ev.target.value) }} 
                            list="{compname}_preset_list_{myrand}" 
                            size={32} 
                            maxlength={1024} 
                            selected={true}
                        >
                    </div>
                    <datalist id="{compname}_preset_list_{myrand}">
                        <select size=8>               
                            {#each presetlist as item}
                                <option key={compname+"_"+myrand+"_presetlist_"+item.id} data-id={item.id} 
                                    value={item.id}>{item.text}
                                </option>
                            {/each}
                        </select>
                    </datalist>
                    <div class="ui_output">Min</div>
                    <div class="ui_input">
                    <input type="number" min="0" 
                            bind:value={template[key].min} 
                            default={template[key].min} 
                            size="3" 
                            maxlength="20"
                         >
                    </div>     
                    <div class="ui_output">Max</div>
                    <div class="ui_input">
                            <input type="number" min="0" 
                                bind:value={template[key].max} 
                                default={template[key].max} 
                                size="3" maxlength="20"
                            >
                    </div>     
                    <div class="ui_output">Regex</div>
                    <div class="ui_input">
                        <input type="text" 
                            bind:value={template[key].regex} 
                            default={template[key].regex} 
                            size="32" 
                            maxlength="255"
                        >
                    </div>    
                    <div class="ui_output">Comment</div>
                    <div class="ui_textarea">
                        <textarea bind:value={template[key].comment} rows=3 cols=64 />
                    </div>    
                    <div class="ui_output">Flags</div> 
                    <checkbox>
                        <div class="ui_checkbox">
                            {#each templateflags as flag,findex}
                                <label>                                
                                        <input type="checkbox" 
                                            name={compname+"_flags_checkbox_"+findex+"_"+myrand} 
                                            key={compname+"_flags_checkbox_"+findex+"_"+myrand} 
                                            on:change={(e) => { updateFlag(key,flag,e); }} 
                                            value={flag}
                                            checked={(template[key].flags != undefined && template[key].flags.includes(flag) ? true : false)}
                                        >

                                        {flag}                                
                                </label>
                            {/each}
                        </div>
                    </checkbox>
                    <div class="ui_output">Default</div>
                    {#if Array.isArray(template[key].default)}
                        <!-- array type -->                        
                        {#each template[key].default as defval,dindex}                            
                            <div class="ui_row">                                  
                                <div class="ui_input"><input type="text" bind:value={template[key].default[dindex]} default={defval}></div>
                                {#if template[key].default.length > 1}
                                    <button class="ui_button" on:click={() => { removeDefault(key,dindex); }}>-</button>
                                {/if}
                                <button class="ui_button" on:click={() => { addDefault(key,dindex); }}>+</button>  
                            </div>                            
                        {/each}                        
                    {:else}
                        <!-- string type -->
                        <div class="ui_row">                            
                            <div class="ui_input"><input type="text" bind:value={template[key].default} default={template[key].default}></div>
                            <button class="ui_button" on:click={() => { addDefault(key); }}>+</button>
                        </div>
                    {/if}
                </div>
            {/each}
        {/key}
        <!-- show update button -->
        <div class="ui_center">
            <button class="ui_button ui_margin_top" on:click={() => { setTemplate() }}>Update</button>
        </div>        
    {/if}    
{/if}

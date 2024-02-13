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
    import { MD } from './_sysschema.js';
    import Icon from './Icon.svelte';
    import { unixtime2ISO } from './_iso8601.js';
    import { int2SI, sortArray } from './_tools.js';
    // component name
    let compname="AuroraBranch";
    // create a random id number of this instance of component
    let myrand = counter++;    
    
    export let id=0;
    export let rerender=0;
    export let treedata;    
    export let execute;
    export let clipboard={};

    // reset the selected option
    // in a select dropdown
    const select_reset = (ev) => {
        // set selectedIndex to zero to reset
        // this works for Firefox
        ev.target.parentElement.selectedIndex = 0;  
        // this works for Chrome
        if (ev.target.options != undefined) { ev.target.options.selectedIndex = 0; }
    };

    const toggleClipboard = () => {       
        // add selection to clipboard
        if (clipboard[id] != undefined) {
            delete clipboard[id];
        } else {
            clipboard[id] = true;            
        }            
        rerender++;
    }    
        
    // formatted, textual information about a dataset
    const formatDatasetInfo = (info) => {
        let result="";
        if (info == undefined) { return ""; }
        // check if this is a open or closed dataset
        if (info[MD["dataset_status"]] == "OPEN") {
            result = result + "Status:\n    OPEN\n" +
                              "Creator:\n    " + info[MD["dc_creator"]] + "\n" +
                              "Description:\n    " + info[MD["dc_description"]] + "\n" +
                              "Created:\n    " + unixtime2ISO(info[MD["dataset_created"]]) + "\n" +
                              "Expire (for closure):\n    " + unixtime2ISO(info[MD["dataset_expire"]]);
        } else if (info[MD["dataset_status"]] == "CLOSED") {
            result = result + "Status:\n    CLOSED (" + unixtime2ISO(info[MD["dataset_closed"]]) + ")\n" +
                              "Creator:\n    " + info[MD["dc_creator"]] + "\n" +
                              "Description:\n    " + info[MD["dc_description"]] + "\n" +
                              "Created:\n    " + unixtime2ISO(info[MD["dataset_created"]]) + "\n" +
                              "Expire (for removal):\n    " + unixtime2ISO(info[MD["dataset_expire"]]) + "\n" +
                              "Size:\n    " + int2SI(info[MD["dataset_size"]]||0);
        }
        // return result of formatting
        return result;
    }

    // textual information about templates on a 
    // specific entity
    const formatTemplateInfo = (info) => {
        let result="";
        if (info == undefined) { return ""; }
        // go through hash keys in alphanumerical order
        let first=true;
        sortArray(Object.keys(info)).forEach((item) => {
            if (first) { result = "Template Assignments: \n\n"; }
            result = result + item + ": ";
            info[item].forEach((tmpl) => {
                result = result + "\n" + "    " + tmpl;
            });
            first = false;
            result = result + "\n\n";
        });
        // return the result
        return result;
    }

</script>

<!-- show the id given -->
{#key rerender}
    {#if treedata[id] != undefined && (String(treedata[id].type).toUpperCase() === "GROUP" || String(treedata[id].type).toUpperCase() === "USER")}
        <!-- group -->        
        <div class="tree_branch">
            <div class="tree_row">
                <div class="tree_row">                    
                    <!-- svelte-ignore a11y-click-events-have-key-events -->
                    <div class="tree_node tree_clickable" on:click={() => { 
                            if ((treedata[id].children.length > 0) || (treedata[id].parent == 1)) { 
                                execute([(treedata[id].expanded == true ? "collapse" : "expand"),id]);
                            } 
                            }}>
                        {(treedata[id].expanded == true ? 
                            String.fromCharCode(9660) : 
                            (treedata[id].children.length > 0 || treedata[id].parent == 1 ? String.fromCharCode(9654) : String.fromCharCode(20)))}                        
                    </div>
                    {#if String(treedata[id].type).toUpperCase() === "GROUP"}
                        <select class="tree_dropdown ui_select_special" on:click={(ev) => { execute(["dropdown",id,ev,treedata[id].type]); select_reset(ev); }}>
                            <option value="NONE" hidden={true} selected={true}>&#8801</option>
                            <option value="create_computer">Create Computer...</option>
                            <option value="create_group">Create Group...</option>
                            <option value="create_script">Create Script...</option>
                            <option value="create_task">Create Task...</option>
                            <option value="create_template">Create Template...</option>
                            <option value="create_user">Create User...</option>
                            <option value="delete">Delete...</option>
                            <option value="set_fistore">FileInterface Store...</option>
                            <option value="members">Members...</option>
                            <option value="move" disabled={(Object.keys(clipboard).length > 0 ? false : true)}>Move Here...</option>
                            <option value="permissions">Permissions...</option>
                            <option value="rename">Rename...</option>                        
                            <option value="selectchildren">Select Children</option>
                            <option value="subscription">Subscriptions...</option>
                            <option value="assign_task">Task Assignments...</option>
                            <option value="assign_template">Template Assignments..</option>
                        </select>
                        <div class="ui_row">
                            <input type="checkbox" 
                                value=1 
                                checked={(clipboard[id] != undefined && clipboard[id] ? true : false)} 
                                on:change={() => { toggleClipboard() }}
                            >
                            <!-- show icon for if group has store-settings on itself or not? -->
                            <div class={(treedata[id].smatch ? "ui_row tree_search_match" : "ui_row" )}>
                                &nbsp;{treedata[id].name}&nbsp;<div class="treecolor_GROUP">(GROUP)</div>
                                {#if treedata[id]["metadata"][MD["fi.store"]] != undefined && treedata[id]["metadata"][MD["fi.store"]] != ""}
                                    <Icon name="folder managed" size="20" fill="#666" popuptext={"Store:\n    "+treedata[id]["metadata"][MD["fi.store"]]} />
                                {/if}
                            </div> 
                            <!-- show icon for template settings if they are set on entity -->
                            {#if treedata[id].templates != undefined && Object.keys(treedata[id].templates).length > 0}
                                <Icon name="template" size="20" fill="#666" 
                                    popuptext={formatTemplateInfo(treedata[id].templates)}
                                />
                            {/if}
                        </div>
                    {/if}
                    {#if String(treedata[id].type).toUpperCase() === "USER"}
                        <select class="tree_dropdown ui_select_special" on:click={(ev) => { execute(["dropdown",id,ev,treedata[id].type]); select_reset(ev); }}>
                            <option value="NONE" hidden={true} selected={true}>&#8801</option>
                            <option value="create_task">Create Task...</option>
                            <option value="delete">Delete...</option>
                            <option value="edit_auth">Edit Authentication...</option>
                            <option value="assign_task">Task Assignments...</option>
                        </select>
                        <div class="ui_row">
                            <input type="checkbox" value={true} checked={(clipboard[id] != undefined && clipboard[id] ? true : false)} on:change={() => { toggleClipboard() }}>
                            <div class={(treedata[id].smatch ? "ui_row tree_search_match" : "ui_row" )}>
                                &nbsp;{treedata[id].name}&nbsp;<div class="treecolor_{String(treedata[id].type).toUpperCase()}">
                                    ({String(treedata[id].type).toUpperCase()})
                                </div>
                            </div>
                        </div>                        
                    {/if}
                </div>
                &nbsp;<div class="tree_hidden">{id}</div>                                
            </div>
            {#if treedata[id].expanded == true}
                <!-- recurse further down the tree with all children of current id -->
                <div class="tree_children">
                    {#each treedata[id].children as item}
                        <!-- invoke component itself -->            
                        <svelte:self treedata={treedata} id={item} bind:rerender={rerender} execute={execute} bind:clipboard={clipboard} />
                    {/each}
                </div>
            {/if}
        </div>            
    {:else if treedata[id] != undefined}
        <!-- non-group entity -->
        <div class="tree_leaf tree_row">
            <!-- draw a fake cadet -->
            <div class="tree_node">&nbsp;</div>
            <!-- generate menus for the various entity types, if any -->
            {#if String(treedata[id].type).toUpperCase() === "COMPUTER"}
                <select class="tree_dropdown ui_select_special" on:click={(ev) => { execute(["dropdown",id,ev,treedata[id].type]); select_reset(ev); }}>
                    <option value="NONE" hidden={true} selected={true}>&#8801</option>                 
                    <option value="create_task">Create Task...</option>                    
                    <option value="delete">Delete...</option>
                    <option value="metadata">Metadata...</option>                    
                    <option value="rename">Rename...</option>                    
                </select>
            {:else if String(treedata[id].type).toUpperCase() === "DATASET"}
                <select class="tree_dropdown ui_select_special" on:click={(ev) => { execute(["dropdown",id,ev,treedata[id].type]); select_reset(ev); }}>
                    <option value="NONE" hidden={true} selected={true}>&#8801</option>
                    <option value="metadata">Metadata...</option>
                    <option value="permissions">Permissions...</option>
                    <option value="remove">Remove...</option>
                </select>   
            {:else if String(treedata[id].type).toUpperCase() === "SCRIPT"}
                <select class="tree_dropdown ui_select_special" on:click={(ev) => { execute(["dropdown",id,ev,treedata[id].type]); select_reset(ev); }}>
                    <option value="NONE" hidden={true} selected={true}>&#8801</option>
                    <option value="run_script">Dashboard...</option>                                     
                    <option value="delete">Delete...</option>                    
                    <option value="permissions">Permissions...</option>
                    <option value="rename">Rename...</option>                    
                </select>             
            {:else if String(treedata[id].type).toUpperCase() === "TASK"}
                <select class="tree_dropdown ui_select_special" on:click={(ev) => { execute(["dropdown",id,ev,treedata[id].type]); select_reset(ev); }}>
                    <option value="NONE" hidden={true} selected={true}>&#8801</option>                                     
                    <option value="delete">Delete...</option>
                    <option value="edit_task">Edit...</option>                     
                    <option value="permissions">Permissions...</option>
                    <option value="rename">Rename...</option>                    
                </select>
            {:else if String(treedata[id].type).toUpperCase() === "TEMPLATE"}
                <select class="tree_dropdown ui_select_special" on:click={(ev) => { execute(["dropdown",id,ev,treedata[id].type]); select_reset(ev); }}>
                    <option value="NONE" hidden={true} selected={true}>&#8801</option>                                     
                    <option value="delete">Delete...</option>
                    <option value="edit_template">Edit...</option>                                                        
                    <option value="permissions">Permissions...</option>
                    <option value="rename">Rename...</option>                    
                </select>
            {:else}
               <!-- draw empty space for those entities without any dropdown menu -->
               <div class="tree_dropdown">&nbsp</div>   
            {/if}
            <div class="ui_row">
                <input type="checkbox" value={true} checked={(clipboard[id] != undefined && clipboard[id] ? true : false)} on:change={() => { toggleClipboard() }}>
                <div class={(treedata[id].smatch ? "ui_row tree_search_match" : "ui_row" )}>
                    <!-- show entity name and type -->
                    &nbsp;{treedata[id].name}&nbsp;<div class="treecolor_{String(treedata[id].type).toUpperCase()}">
                        ({String(treedata[id].type).toUpperCase()})                        
                    </div>
                    <!-- check if we have a dataset type -->
                    {#if String(treedata[id].type).toUpperCase() === "DATASET" && treedata[id]["metadata"][MD["dataset_status"]] != undefined}
                        <!-- show icons and dataset data for either a open or closed dataset, including metadata for dataset -->
                        {#if treedata[id]["metadata"][MD["dataset_status"]] == "OPEN"}
                            <Icon name="lock open" size="20" fill="#666" 
                                popuptext={formatDatasetInfo(treedata[id]["metadata"])}
                            />
                        {:else if treedata[id]["metadata"][MD["dataset_status"]] == "CLOSED"}
                            <Icon name="lock closed" size="20" fill="#666" 
                                popuptext={formatDatasetInfo(treedata[id]["metadata"])} 
                            />
                        {/if}
                        <!-- show icons for dataset data present or removed -->
                        {#if treedata[id]["metadata"][MD["dataset_status"]] == "CLOSED" && treedata[id]["metadata"][MD["dataset_removed"]] == 0}
                            <Icon name="folder" size="20" fill="#666" popuptext={"Dataset Data Present"} />
                        {:else if treedata[id]["metadata"][MD["dataset_status"]] == "CLOSED" && treedata[id]["metadata"][MD["dataset_removed"]] > 0}
                            <Icon name="folder off" size="20" fill="#666" popuptext={"Dataset Data Removed"} />
                        {/if}
                        <!-- show icons for dataset automated or manual type -->
                        {#if treedata[id]["metadata"][MD["dataset_type"]] == "AUTOMATED"}
                            <Icon name="automated" size="20" fill="#666" popuptext={"Automated Dataset"} />
                        {:else}
                            <Icon name="manual" size="20" fill="#666" popuptext={"Manual Dataset"} />
                        {/if}
                    {/if}
                </div>
            </div>
            <div class="tree_hidden">&nbsp;{id}</div>            
        </div>
    {/if}
{/key}

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
    let compname="AuroraTree";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";        
    import Status from "./Status.svelte";
    import Auth from "./Auth.svelte";
    import Icon from "./Icon.svelte";
    import MetadataEditor from "./MetadataEditor.svelte";
    import Permissions from "./Permissions.svelte";
    import Members from "./Members.svelte";
    import DeleteEntity from "./DeleteEntity.svelte";
    import MoveEntity from "./MoveEntity.svelte";
    import RenameEntity from "./RenameEntity.svelte";
    import SetFileInterfaceStore from "./SetFileInterfaceStore.svelte";
    import Template from "./Template.svelte";
    import Modal from "./Modal.svelte";
    import AuroraBranch from "./AuroraBranch.svelte";
    import Assign from "./Assign.svelte";
    import TaskEditor from "./TaskEditor.svelte";
    import { AuroraTreeCache } from "./_auroratreecache.js";
    import { onMount } from 'svelte';   
    import { getCookieValue, setCookieValue, string2Boolean, string2Number } from "./_cookies";
    import Subscription from "./Subscription.svelte";
    import TaskAssign from "./TaskAssign.svelte";
    import ScriptEditor from "./ScriptEditor.svelte";
    import ScriptExecuter from "./ScriptExecuter.svelte";

    let CFG={};
    let disabled=false;

    let cache = new AuroraTreeCache();
    let treedata={};
    // selection clipboard for the entity tree
    // contains a list of selected entities
    let clipboard={};
    // searchstr when searching
    let searchstr="";
    let smatchcount=0;
   
    let updating=false;
    let rerender=0;

    // id variable to use when needed for various menu operations
    let id=0;
    let type="";

    let showadvanced=false;
    let show_assign=false;
    let show_createcomputer=false;
    let show_creategroup=false;
    let show_createtask=false;
    let show_createtemplate=false;
    let show_createuser=false;
    let show_createscript=false;
    let show_permissions=false;
    let show_members=false;
    let show_delete=false;
    let show_delete_selection=false;
    let show_rename=false;
    let show_metadata=false;
    let show_move=false;
    let show_auth=false;
    let show_setstore=false;
    let show_subscription=false;
    let show_taskedit=false;
    let show_taskassign=false;
    let show_template=false;
    let show_runscript=false;
    let codestart=1;

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        // get treedata
        updating=true;
        let data = await cache.get();
        treedata=data;
        data = await getCookieValues(data);
        updating=false;
        if (data != undefined) {
            // set treedata
            treedata=data;
            rerender++;
        }
    });

    // get cookie values for the tree-view
    async function getCookieValues(data) {
        // check if we have cookie data on expanded branches        
        const expandedstr = getCookieValue(CFG["www.cookiename"],"treeexpanded");
        // check if we have value for showing datasets
        const shdsets = string2Boolean(getCookieValue(CFG["www.cookiename"],"treeshowdataset"));
        // check if we have value for showing users
        const shusers = string2Boolean(getCookieValue(CFG["www.cookiename"],"treeshowuser"));
        // check if we have value for showing template metadata
        const shtmplmd = string2Number(getCookieValue(CFG["www.cookiename"],"treeshowtmplmd"));
        if (shtmplmd != undefined) {
            // get current params values
            let ps=cache.params();
            // set value of template metadata
            ps.templatemetadata=shtmplmd;
            // update cache instance with new value
            cache.params(ps);
        }
        if ((shdsets != undefined) || (shusers != undefined)) { 
            let values = {};
            if (shdsets != undefined) { values["DATASET"]=shdsets; }
            if (shusers != undefined) { values["USER"]=shusers; }
            // get the current global exclude values in the cache
            let exclude=cache.exclude();
            for (let key in values) {
                // set type of operation
                let type = key;
                // get value of operation
                let show = values[key];          
                // get position of type element in exclude array, if at all
                let pos=exclude.indexOf(type);
                if (show == true) {
                    // we are to show the type
                    if (pos >= 0) {
                        // type element found, remove it
                        exclude.splice(pos,1);
                    }
                } else {
                    // we are to hide the type
                    if (pos < 0) {
                        // type element not found, add it to exclude
                        exclude.push(type);
                    }
                }
            }
            // update cache-instance
            cache.exclude(exclude);        
        }
        // convert from json to hash object
        let expanded=[];
        try {
            expanded = JSON.parse(expandedstr);
        } catch {
            // we failed - set empty array
            expanded=[];
        }            
        // go through each entry in expanded and modify the tree-data
        if (expanded != undefined) {
            for (let i=0; i < expanded.length; i++) {
                // set this part of the tree as expanded
                await recursiveExpand(expanded[i])                
            }
        }
        // update data
        data=await cache.get();
        // return the result
        return data;
    }

    // save tree-view settings/expanded branches in cookie
    const setCookieValues = (data) => {
        // go through data and pick out expansions
        let expanded = [];
        for (let key in data) {
            if (data[key].expanded) {
                // this entity id is expanded, add it to array
                expanded.push(key);
            }
        }
        // store array in cookie
        setCookieValue(CFG["www.cookiename"],"treeexpanded",JSON.stringify(expanded),CFG["www.domain"],CFG["www.cookie.timeout"],"/");
        // store show datasets value
        setCookieValue(CFG["www.cookiename"],"treeshowdataset",(String(cache.exclude().includes("DATASET")) == "true" ? false : true),CFG["www.domain"],CFG["www.cookie.timeout"],"/");
        // store show users value
        setCookieValue(CFG["www.cookiename"],"treeshowuser",(String(cache.exclude().includes("USER")) == "true" ? false : true),CFG["www.domain"],CFG["www.cookie.timeout"],"/");
        // store template value
        setCookieValue(CFG["www.cookiename"],"treeshowtmplmd",(cache.params().templatemetadata != undefined && cache.params().templatemetadata == 1 ? 1 : 0),CFG["www.domain"],CFG["www.cookie.timeout"],"/");
    };

    async function tree_do(pars) {
        let cmd=pars[0] || "";
        let data;
        updating=true;        
        let changed=false;
        if (cmd == "expand") {
            data=await cache.expand(pars[1]);        
            changed=true;
        } else if (cmd == "collapse") {        
            data=await cache.collapse(pars[1]);                    
            changed=true;        
        } else if (cmd == "dropdown") {
            // this is from a tree-branch dropdown menu
            id=pars[1] || 0;
            let ev=pars[2];
            let subcmd=ev.target.value;
            if (subcmd == "assign_template") {
                type="group";
                show_assign=true;
            } else if (subcmd == "create_computer") {
                type="computer";
                show_createcomputer=true;
            } else if (subcmd == "create_group") {
                type="group";
                show_creategroup=true;
            } else if (subcmd == "create_script") {
                type="script";
                show_createscript=true;
            } else if (subcmd == "create_task") {
                type="task";
                show_createtask=true;
            } else if (subcmd == "create_template") {
                type="template";
                show_createtemplate=true;
            } else if (subcmd == "create_user") {
                type="user";
                show_createuser=true;
            } else if (subcmd == "delete") {                
                show_delete=true;
            } else if (subcmd == "delete_selection") {                                     
                show_delete_selection=true;
            } else if (subcmd == "edit_auth") {                
                show_auth=true;     
            } else if (subcmd == "edit_task") {                
                show_taskedit=true;            
            } else if (subcmd == "run_script") {              
                show_runscript=true; 
            } else if (subcmd == "assign_task") {
                show_taskassign=true;
            } else if (subcmd == "edit_template") {                
                show_template=true;                         
            } else if (subcmd == "members") {                
                show_members=true;
            } else if (subcmd == "metadata") {
                type=pars[3] || "DATASET";               
                show_metadata=true;
            } else if (subcmd == "subscription") {                
                show_subscription=true;    
            } else if (subcmd == "move") {
                show_move=true;
            } else if (subcmd == "permissions") {
                type=pars[3] || "DATASET";
                show_permissions=true;
            } else if (subcmd == "rename") {                
                show_rename=true;
            } else if (subcmd == "set_fistore") {                
                show_setstore=true;    
            } else if (subcmd == "selectchildren") {
                // multiple entities was selected - add to clipboard
                // id is the parent of all the selected children
                for (let i=0; i < treedata[id].children.length; i++) {
                    // add child to clipboard
                    clipboard[treedata[id].children[i]]=true;
                }
                // rerender interface
                rerender++;
            } else if (subcmd == "selectclear") {
                // reset/clear contents of clipboard                
                clipboard={};
                // rerender tree
                rerender++;
            }
        } else if ((cmd == "show_datasets") || (cmd == "show_users")) {
            // set entity type for operation
            let type = (cmd == "show_datasets" ? "DATASET" : "USER");
            // get event value and determine if we hide or show the entity type
            let hide = pars[1].target.value;
            // get the current global exclude values in the cache
            let exclude=cache.exclude();
            // get position of type element in exclude array, if at all
            let pos=exclude.indexOf(type);
            if (hide == "false") {
                // we are to show the type
                if (pos >= 0) {
                    // type element found, remove it
                    exclude.splice(pos,1);
                }
            } else {
                // we are to hide the type
                if (pos < 0) {
                    // type element not found, add it to exclude
                    exclude.push(type);
                }
            }    
            // update cache-instance
            cache.exclude(exclude);
            // update data
            data=await cache.get();   
            // tree has changed
            changed=true;
        } else if (cmd == "show_tmplmd") {
            let val = pars[1].target.value;
            val = (String(val) === "1" ? 1 : 0);
            // get current params
            let ps=cache.params();
            // set template metadata value
            ps.templatemetadata = val;
            // update cache-instance
            cache.params(ps);           
            // update data
            data=await cache.get();
            // tree has changed
            changed=true;
        }
        updating=false;
        // only update tree if we had an actual update
        if (changed) {
            treedata = data; 
            // reset search matches since tree has changed
            resetSearch();
            // update cookie about expaded entries
            setCookieValues(data);
            // rerender tree       
            rerender++;
        }    
    }

    async function closeOperation(name) {  
        let ids=[]; 
        if (name == "refresh") {
            updating=true;
        } else if (name == "resetselect") {
            clipboard={};
            rerender++;
        }
        if (name == "assign_template") {
            show_assign=false;                        
        } else if (name == "create_computer") {
            show_createcomputer=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "create_group") {
            show_creategroup=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "create_script") {
            show_createscript=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "create_task") {
            show_createtask=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "create_template") {
            show_createtemplate=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "create_user") {
            show_createuser=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "delete") {
            show_delete=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "delete_selection") {
            show_delete_selection=false;
            updating=true;
            // add all clipboard ids
            for (let key in clipboard) {
                // add clipboard key to ids
                ids.push(key);                
            } 
            // reset clipboard now that they have been deleted
            clipboard={};                      
        } else if (name == "edit_auth") {
            show_auth=false;    
        } else if (name == "subscription") {
            show_subscription=false;
        } else if (name == "edit_task") {
            show_taskedit=false;                        
            updating=true;
            ids.push(id);                        
        } else if (name == "run_script") {
            show_runscript=false;                        
            updating=false;               
        } else if (name == "edit_template") {
            show_template=false;   
            updating=true;
            ids.push(id);                     
        } else if (name == "metadata") {
            show_metadata=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "move") {
            show_move=false;
            updating=true;
            // add all clipboard ids
            for (let key in clipboard) {
                // add clipboard key to ids
                ids.push(key);                
            }
            // add parent for where entity(-ies) are moved to
            ids.push(id);        
        } else if (name == "permissions") {
            show_permissions=false;
        } else if (name == "rename") {
            show_rename=false;
            updating=true;
            // add id to ids so the cache is refreshed
            // more efficiently
            ids.push(id);
        } else if (name == "set_fistore") {
            show_setstore=false;
            updating=false;
        } else if (name == "assign_task") {
            show_taskassign=false;
        }

        if (updating) {
            // we need to update the cache
            let data;
            if (ids.length > 0) {
                // we have ids, so we attempt to do a quicker
                // refresh of the cache
                data = await cache.refresh(ids);                
            } else {
                // just refresh the whole cache
                data = await cache.refresh();
            }
            updating=false;            
            // reassignment of treedata should ensure rerendering
            treedata = data;           
            // reset search markings since we have refreshed the tree
            resetSearch();
        }
    }

    // close all possible modals
    const cancelModal = () => {
        show_assign=false;
        show_createcomputer=false;
        show_creategroup=false;
        show_createtask=false;
        show_createtemplate=false;
        show_createuser=false;
        show_setstore=false;
        show_permissions=false;
        show_members=false;
        show_delete=false;
        show_delete_selection=false;
        show_rename=false;
        show_metadata=false;
        show_auth=false;
        show_move=false;
        show_subscription=false;
        show_taskedit=false;
        show_template=false;
        show_taskassign=false;
        show_createscript=false;
        show_runscript=false;
    };

    // reset search markings on the entity tree
    const resetSearch = () => {
        // go through the whole tree and reset search
        for (let key in treedata) {
            if (treedata[key].smatch) {
                // it has been set - remove it
                delete treedata[key].smatch;
            }
        }
        // reset search match counter as well
        smatchcount=0;
    };

    async function recursiveExpand(id) {
        if (treedata[id] == undefined) { return; }
        // expand this group        
        if ((treedata[id].type == "GROUP") && (!treedata[id].expanded)) { await cache.expand(id); }
        let parent = treedata[id].parent;
        // recursively expand all 
        if (id != 1) {
            await recursiveExpand(parent);
        }
    }

    // search the entity tree for matches
    async function searchTree () {
        // if searchstr is blank or spaces, reset search and return
        if ((searchstr == "") || (/^\s+$/.test(searchstr))) { resetSearch(); rerender++; return; }
        // construct regex
        var regex = new RegExp(searchstr, "gi");
        // reset search-matches
        resetSearch();
        // search entity tree for entities
        for (let key in treedata) {
            // check if given key matches search or not
            if ((treedata[key] != undefined) && ((regex.test(key)) || (regex.test(treedata[key].name)))) {
                // we have a match - tag it as found in search
                treedata[key].smatch=true;
                // expand all groups down to this entity
                await recursiveExpand(key);
                // increment smatchcounter
                smatchcount++;
            }
        }
        // rerender
        rerender++;
    }

    const handleSearch = (ev) => {
        if ((ev != undefined) & (ev.keyCode == 13)) {
            // start search
            searchTree();
            // update cookie on the latest
            setCookieValues(treedata);
        }    
    };
</script>

{#if !disabled}
    {#if updating}
        <Status message="Updating tree cache..." type="processing" />
    {/if}

    <div class="ui_title ui_center">Manage Entity Tree</div>

    <!-- svelte-ignore a11y-click-events-have-key-events -->
    <div on:click={() => { showadvanced = !showadvanced}}>
        <div class="ui_center">
            <div class="ui_center ui_margin_top">
                {#if showadvanced}
                    <Icon name="unfoldless" fill="#555" size="40" />
                {:else}
                    <Icon name="unfoldmore" fill="#555" size="40" />
                {/if}
            </div>
        </div>
    </div> 

    <!-- show advanced settings that user can change -->
    {#if showadvanced && treedata !== undefined}
    <div class="ui_center">
        <div class="ui_output">Show Datasets</div>
        <select class="ui_input" on:change={(ev) => { tree_do(["show_datasets",ev]); }}>
            <option value={false} selected={(String(cache.exclude().includes("DATASET")) == "true" ? false : true)}>Show Dataset</option>
            <option value={true} selected={(String(cache.exclude().includes("DATASET"))  == "true" ? true : false)}>Hide Dataset</option>
        </select>        

        <div class="ui_output">Show Users</div>
        <select class="ui_input" on:change={(ev) => { tree_do(["show_users",ev]); }}>
            <option value={false} selected={(String(cache.exclude().includes("USER")) == "true" ? false : true)}>Show User</option>
            <option value={true} selected={(String(cache.exclude().includes("USER"))  == "true" ? true : false)}>Hide User</option>
        </select> 

        <div class="ui_output">Show Template Metadata</div>
        <select class="ui_input" on:change={(ev) => { tree_do(["show_tmplmd",ev]); }}>
            <option value="1" selected={(String(cache.params().templatemetadata||0) == "1" ? true : false)}>Show Template Metadata</option>
            <option value="0" selected={(String(cache.params().templatemetadata||0) == "1" ? false : true)}>Hide Template Metadata</option>
        </select>       
    </div>
    {/if}

    <div class="ui_margin_left">
        <button class="ui_button" on:click={() => { closeOperation("refresh") }}>Refresh</button>
        <button class="ui_button" on:click={() => { closeOperation("resetselect") }}>Reset Selection</button>
        <!-- only show delete button if items have been selected -->
        {#if Object.keys(clipboard).length > 0}
            <button class="ui_button" on:click={() => { tree_do(["dropdown",Object.keys(clipboard),{ target: { value: "delete_selection" } }]); }}>Delete Selection</button>
        {/if}   
        <!-- show number of selected items -->
        {Object.keys(clipboard).length} entities have been selected

        <!-- show search input -->
        <div class="ui_row ui_margin_top">
            <div class="ui_input">
                <input on:keypress={(ev) => { handleSearch(ev); }} type="text" bind:value={searchstr} default={searchstr}>
            </div>
            <button class="ui_button" on:click={() => { searchTree(); }}>Search</button>
            {#if smatchcount > 0}
                Found {smatchcount} entities
            {/if}
        </div>
    </div>

    <!-- show the tree -->
    {#if treedata !== undefined}
        <div class="ui_margin_top">
            <AuroraBranch id=1 treedata={treedata} bind:rerender={rerender} execute={tree_do} bind:clipboard={clipboard} />    
        </div>
    {/if}

    <!-- show other menu operations -->
    {#if show_assign}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <Assign id={id} closeHandle={() => { closeOperation("assign_template"); }} />
        </Modal>
    {/if}

    {#if show_auth}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <Auth id={id} closeHandle={() => { closeOperation("edit_auth"); }} />
        </Modal>
    {/if}

    {#if show_createcomputer || show_creategroup || show_createtask || show_createuser || show_createtemplate || show_createscript}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <MetadataEditor type={type} parent={id} finishedHandle={() => {closeOperation("create_"+type)}} />
        </Modal>
    {/if}

    {#if show_delete}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <DeleteEntity id={id} closeHandle={() => { closeOperation("delete"); }} />
        </Modal>
    {/if}

    {#if show_delete_selection}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <DeleteEntity id={id} closeHandle={() => { closeOperation("delete_selection"); }} />
        </Modal>
    {/if}

    {#if show_members}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <Members id={id} />
        </Modal>
    {/if}

    {#if show_metadata}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <MetadataEditor type={type} id={id} finishedHandle={() => {closeOperation("metadata")}} />
        </Modal>
    {/if}

    {#if show_move}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <MoveEntity id={Object.keys(clipboard)} parent={id} closeHandle={() => { closeOperation("move"); }} />
        </Modal>
    {/if}

    {#if show_permissions}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <Permissions id={id} type={type} />
        </Modal>
    {/if}

    {#if show_rename}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <RenameEntity id={id} closeHandle={() => { closeOperation("rename"); }} />
        </Modal>
    {/if}   

    {#if show_runscript}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <div class="ui_center">
                <div class="ui_center_row ui_title">Scripting Dashboard</div>
                <div class="ui_center_row">
                    <div class="ui_output">{treedata[id].name}</div>                
                </div>  
                <div>  
                    <div class="ui_row ui_margin_top">
                        <div style="width: 49%;">
                            <ScriptExecuter 
                                id={id}
                                closeHandle={() => { closeOperation("run_script"); }}
                                closebutton={false}
                                showheader={false}
                                bind:library_linecount={codestart}
                            />
                        </div>    
                        <div style="width: 49%;">
                            <ScriptEditor
                                id={id}
                                startline={codestart}
                                closeHandle={() => { closeOperation("run_script"); }}
                                closebutton={false}
                                showheader={false}
                            />    
                        </div>    
                    </div>
                </div>
            </div>
        </Modal>        
    {/if}

    {#if show_setstore}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <SetFileInterfaceStore id={id} closeHandle={() => { closeOperation("set_fistore"); }} />
        </Modal>
    {/if}

    {#if show_subscription}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <Subscription id={id} closeHandle={() => { closeOperation("subscription"); }} />
        </Modal>
    {/if}

    {#if show_taskedit}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <TaskEditor id={id} closeHandle={() => { closeOperation("edit_task"); }} />
        </Modal>        
    {/if}

    {#if show_taskassign}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <TaskAssign id={id} closeHandle={() => { closeOperation("task_assign"); }} />
        </Modal>        
    {/if}

    {#if show_template}
        <Modal width="70" height="70" border={false} closeHandle={() => {cancelModal()}}>
            <Template id={id} closeHandle={() => { closeOperation("edit_template"); }} />
        </Modal>
    {/if}
{:else}
    {window.location.href=CFG["www.base"]}    
{/if}

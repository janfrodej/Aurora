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

    Description: Loading, running and viewing a Lua script inside the AURORA environment.
-->
<script context="module">
    // unique counter for instances of component
    let counter = 0;
</script>

<script>
    // component name
    let compname="ScriptExecuter";
    // create a random id number of this instance of component
    let myrand = counter++;    
    import { getConfig } from "./_config";    
    import { call_aurora } from "./_aurora.js";   
    import Status from "./Status.svelte";
    import { onMount } from 'svelte';
    import Icon from "./Icon.svelte";
    import { LuaFactory } from 'wasmoon/dist/index.js';
   
    let factory;
    let lua;

    let CFG={};
    
    let disabled=false;    

    // some input/output variables
    export let id = 0;
    id=Number(id);
    export let closeHandle;
    export let closebutton = true;
    export let showheader = true;
    export let library_linecount = 1;

    // some promises
    let data;
    
    // some variables    
    let show = false;
    let name = "";
    let script = "";
    let luaout = "";
    let luain = "";
    let luainbutton;
    let luareturn = "";    
    let luarunning = false;
    let luaerror = false;
    let luaerrorline = 0;
    let readinputmess="";
    let outputarea;

    const luaOut = (str) => {
       // add string to the luaOut content 
       luaout = luaout + str;
       // move scroll to end in order to follow text
       outputarea.scrollTop=outputarea.scrollHeight;
       return "";
    }

    // fetches input to the lua script through the
    // input field in the DOM
    async function luaIn(msg,def) {
        // set message in dialog window according to parameter
        if ((msg != undefined) && (msg != "")) { readinputmess = msg; }
        else { readinputmess = ""; }
        if ((def != undefined) && (def != "")) { luain=def; }
        else { luain=""; }
        // wait for click of send-button
        await handleButtonClick(luainbutton);
        // return the luainvalue just for returning something
        return luain;
    }

    // the button click handler for the send-button
    async function handleButtonClick(btn) {     
       return new Promise(resolve =>  btn.onclick = () => { resolve()});
    }

    const luaTopLevelCode = () => {
        let code = "\n";
        return code;
    }
    
    // lua code to be able to dump/convert variables/data structures to textual representation
    // for inspection and other uses
    const luaDumperCode = () => {
        let code = "\n" +
            "-- nil, boolean, number, string, userdata, function, thread, and table\n" +
            "function dumper(o,s,l,g)\n" +
            "   if (type(s) == \"nil\") then s = \"VAR = \"; l = 2; end\n" +
            "   if (type(l) == \"nil\") then l = 1; end\n" +
            "   if (type(g) == \"nil\") then g = false; end\n" +
            "   if (type(o) == \"nil\") then\n" +
            "      s = s .. \"nil\"\n" +
            "   elseif (type(o) == \"boolean\") then\n" +
            "       if (o) then\n" +
            "           s = s .. \"true,\"\n" +
            "       else\n" +
            "           s = s .. \"false,\"\n" +
            "       end\n" +
            "   elseif (type(o) == \"number\") then\n" +
            "       s = s .. o .. \",\";\n" +
            "   elseif (type(o) == \"string\") then\n" +
            "       if (o == nil) then o=\"nil\"; end\n" +
            "       s = s .. \"\\\"\" .. o .. \"\\\",\";\n" +
            "   elseif (type(o) == \"userdata\") then\n" +
            "       -- userdata - dump through metatable\n" +
            "       t=getmetatable(o);\n" +
            "       if (t == nil) or ((type(t) == \"string\") and (t == \"protected metatable\")) then\n" +
            "           -- this userdata is a black hole. Unable to dump its content\n" +
            "           -- perhaps over billions of years its information will slowly come out again\n" +
            "           s = s .. \"(USERDATA),\";\n" +
            "       else\n" +
            "           -- metatable was readable, we should be able to iterate\n" +
            "           s = s .. \"{\";\n" +
            "           for k,v in ipairs(o) do\n" +
            "               s = s .. \"\\n\" .. indents(l,3) .. k .. \": \";\n" +
            "               s = dumper(v,s,l+1,true);\n" +
            "           end\n" +
            "           s = s .. \"\\n\" .. indents(l-1,3) .. \"},\\n\";\n" +
            "       end\n" +
            "   elseif (type(o) == \"function\") then\n" +
            "       s = s .. \"(function),\";\n" +
            "   elseif (type(o) == \"thread\") then\n" +
            "       s = s .. \"(thread),\";\n" +
            "   elseif (type(o) == \"table\") then\n" +
            "       -- go through each key and recurse\n" +
            "       s = s .. \"{\";\n" +
            "       for k,v in pairs(o) do\n" +
            "           s = s .. \"\\n\" .. indents(l,3) .. k .. \": \";\n" +
            "           s = dumper(v,s,l+1,true);\n" +
            "       end\n" +
            "       s = s .. \"\\n\" .. indents(l-1,3) .. \"},\\n\";\n" +
            "   end\n" +
            "   -- add eol if o is not part of a group (g)\n" +
            "   if (g == false) then s = s .. \"\\n\"; end\n" +
            "   -- return resultant string\n" +
            "   return s;\n" +
            "end\n\n";
        return code;
    }
    
    // lua code to handle calling and waiting for AURORA REST-server
    const luaAuroraCode = () => {
        let code = "\n" +
            "function aurora(method,params,notify)\n" +
            "   -- call aurora and wait and spare user the extra coding\n" +
            "   if (type(notify) == \"nil\") then notify = true; end\n" +
            "   result = call_aurora(method,params):await();\n" +
            "   if (result == nil) and (notify) then print (\"Critical error calling AURORA. No error-message received...\"); o={}; return o; end\n" +
            "   if (result.err ~= 0) and (notify) then\n" +
            "       print (\"Error calling AURORA: \" .. result.errstr .. \"\\n\");\n" +
            "   end\n" + 
            "   return result;\n" +
            "end\n\n";
        return code;
    }

    const luaReadCode = () => {
        let code = "\n" +
            "function readstr(msg,def)\n" +
            "   -- check if we have a message to show\n" +
            "   if (msg ~= nil) and (msg ~= \"\") then print (msg); end\n" +
            "   -- call the readinput js function and wait\n" +
            "   result = readinput(msg,def):await();\n" +
            "   -- return result to caller\n" +
            "   return result;\n" +
            "end\n\n";
        return code;
    }

    async function createLua() {
        // create lua instance...
        factory = new LuaFactory('/wasmoon.wasm');
        //factory = new LuaFactory();
        lua = await factory.createEngine({enableProxy:false, injectObjects: true});      
        // define lua library function to call aurora
        lua.global.set('call_aurora', (method,params) => {
            return new Promise (async (resolve) => { 
                let res=await call_aurora(method,params,false);                
                resolve(res);
            }); 
        });
        // overwrite print function so that stdout goes to our place of choice
        lua.global.set('print',(str) => { luaOut(str); });
        // return string with n x m number of indents
        lua.global.set('indents',(n,m) => {
            if (n === undefined) { n = 0; }
            if (m === undefined) { m = 1; }
            n = Number(n);
            m = Number(m);
            let str = "";
            for (let i=0; i < n; i++) {
                for (let j=0; j < m; j++) {
                    str = str + " ";
                }
            }
            // return resultant string
            return str;
        });
        // define way to read input
        lua.global.set('readinput',(msg,def) => { 
            return new Promise (async (resolve) => {            
               await luaIn(msg,def);
               // return value from input box
               resolve(luain);             
               // reset values
               readinputmess="";
               luain="";
            });
        });
        lua.global.set('split',(str,sep,limit) => {
            str = (str == undefined ? "" : str);
            sep = (sep == undefined || sep == "" ? "," : sep);
            let arr = String(str).split(sep,limit);
            return arr;
        });
        return "";
    }

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();
        // update disabled
        disabled = CFG["www.maintenance"]||false;
        // create the lua environment
        await createLua();
        // get remaining data
        data = getData();        
        // calculate number of lines in included lua code
        let s=luaTopLevelCode() + luaDumperCode() + luaReadCode() + luaAuroraCode();
        library_linecount = s.split(/\r\n|\r|\n/).length;
    });      
    
    async function executeScript() {
        // check that we are not running already
        if (!luarunning) {
            // lua is running
            luarunning = true;
            // reset error
            luaerror = false;
            luaerrorline = 0;
            // reset output area
            luaout = "";
            // reset result
            let luaresult = "";
            let res={ message: "" };
            // compose code to run, including added functions
            let code = luaTopLevelCode() + luaDumperCode() + luaReadCode() + luaAuroraCode() + script;
            // catch any issues
            try {
                luaOut("EXECUTION STARTED...\n\n");                
                luareturn = await lua.doString(code);
            } catch (err) {     
                res.message = err.message;
                luaerror = true;  
                // attempt to locate line number in error            
                let m = err.message.match(/^\[[^\]]+\]\:(\d+)\:/);
                if ((m != undefined) && (m[1] != undefined) && (/^\d+$/.test(String(m[1])))) {
                    // we have a match on the line number of the errors
                    luaerrorline = m[1];
                }
            } finally {
                //
            }
            
            if (res.message !== "") {
                // something failed - return
                luaresult = res.message;
                if (luaresult == "index out of bounds") {
                    luaOut("\n\nEXECUTION ABORTED...");
                } else {
                    luaOut("\n\nEXECUTION STOPPED: "+luaresult);
                }    
            } else {
                luaOut("\n\nEXECUTION FINISHED..."); 
            }
            luarunning=false;
        }    
    }

    // get all data needed 
    async function getData () {    
        show = false;
       
        // get the script
        let params={};
        params["id"] = id;
        let getscript = await call_aurora("getScript",params);
        if (getscript.err == 0) {
            // get the script
            script = getscript.script;
            name = getscript.name;
            show = true;
            return 1;
        } else { return 0; }
    };

    async function stopScript() {
        // reset the lua environment
        lua.global.close();
        // create the lua environment again
        await createLua();
        // generate click event, just to ensure it ends
        luainbutton.click();
        return "";
    }

    const resetOutput = () => {
        luaout="";
        // return blank string 
        // to avoid noise in render
        return "";
    }

    const handleInputKeypress = (ev) => {
        // key pressed - check if it is enter
        if ((ev != undefined) && (ev.keyCode == 13)) {
            // enter was pressed - generate on-click event
            luainbutton.click();
        }
    };
</script>

<!-- Rendering -->
{#if !disabled}
    {#if data != undefined}
        {#await data}
            <Status message="Retrieving/updating script..." type="processing" />
        {:then}
           {resetOutput()}    
        {/await}
    {/if}
    {#if show}
        {#if showheader}
            <!-- show title and table with entity metadata -->
            <div class="ui_title ui_center">Run Script</div>              
            <div class="ui_center">
                <div class="ui_output">Script Name</div>
                <div class="ui_output">{name}</div>
            </div>
        
        {/if}    
        <div class="scriptexecuter_row">
            {#if luarunning}
                <Icon name="play"
                    size="40"
                    fill="#777"
                    margin="0.5rem"
                    popuptext="Running..."
                />
                <Icon name="stop"
                    size="40"
                    fill="#555"
                    margin="0.5rem"
                    on:click={() => { stopScript() }}
                    popuptext="Stop"
                />
            {:else}
                <Icon name="play"
                    size="40"
                    fill="#555"
                    margin="0.5rem"
                    on:click={() => { executeScript() }}
                    popuptext="Run"
                />
                <Icon name="stop"
                    size="40"
                    fill="#777"
                    margin="0.5rem"
                    popuptext="Stop is disabled while script is not running"
                />    
            {/if}
            {#if closebutton}
                <button class="ui_button" on:click={() => { lua.global.close(); closeHandle(); }}>Close</button>            
            {/if}
            <!-- &nbsp;STDIN&nbsp; -->                       
            <!-- <div class="ui_output">{readinputmess}</div> -->
            <div class="ui_input">
                <input type="text" bind:value={luain} on:keypress={(ev) => { handleInputKeypress(ev); }} disabled={!luarunning} />
            </div>
            <button
                class="ui_button"
                bind:this={luainbutton}
                hidden={true}
            >
            </button>
            {#if !luarunning}
                <Icon name="send"
                    size="40" 
                    fill="#777"
                    margin="0.5rem"
                    on:click={() => { luainbutton.click(); }}
                    popuptext="Send is disabled while script is not running"
                />
                <Icon name="refresh"
                    size="40"
                    fill="#555"
                    margin="0.5rem"
                    on:click={() => { data=getData(); }}
                    popuptext="Reload"
                />
            {:else}
                <Icon name="send"
                    size="40" 
                    fill="#555"
                    margin="0.5rem"
                    on:click={() => { luainbutton.click(); }}
                    popuptext="Send"
                />
                <Icon name="refresh"
                    size="40"
                    fill="#777"
                    margin="0.5rem"
                    popuptext="Reload Disabled while script is running"
                />
            {/if}
        </div>
        <div class="scriptexecuter_container">        
            <div class="scriptexecuter_row">
                <textarea
                    bind:value={luaout}
                    bind:this={outputarea}
                    cols="150"
                    rows="20"
                    readonly={true}
                />
            </div>
        </div>
    {/if}    
{/if}

<style>
    .scriptexecuter_container {
        display: flex;
        flex-basis: auto;
        font-family: Consolas, "Courier New", Courier, monospace;
    }

    .scriptexecuter_row {
        display: flex;
        justify-content: left;
        align-items:left;
        flex-direction: row;
        text-align: left;
    }

    .scriptexecuter_container textarea {
        border: none;
        width: 100%;
        overflow: scroll;
        resize: none;
        max-height: 200px;
        white-space: pre;
        margin-top: 20px;
    }
</style>

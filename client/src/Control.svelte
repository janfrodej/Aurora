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

    Description: Setup a tunnell to remote control a computer in the AURORA entity tree.
-->
<script> 
    import { getConfig } from "./_config";       
    import InputSearchList from "./InputSearchList.svelte";      
    import { onMount } from 'svelte';
    import { call_aurora } from "./_aurora.js";
    import { hash2SortedSelect } from "./_tools.js";    
    import Status from "./Status.svelte";
    
    let CFG={};
    let disabled=false;    
    let ipaction="";
    let computerval="";
    let curcomputerval="";
    let computers=[];
    let cmpprom;    
    let prot;
    let protocolhash={};
    let protocols=[];
    let protocolval="";
    let ip="N/A";
    let tunneldata={};
    let tunprom;
    let showdata=false;

    $: protocolval && (showdata = false);

    // handles first time logon attempt
    onMount(async () => {        
        // fetch configuration and wait
        CFG =  await getConfig();
        // set disabled
        disabled = CFG["www.maintenance"]||false;
        // update ipaction
        ipaction=CFG["gatekeeper.ipv4resolver"]
        // attempt an authentication automatically
        // and thereby check our credentials
        // we will be redirected to login-page if it fails
	    call_aurora("doAuth",undefined);    
        // get computers    
        cmpprom=getComputers();      
        // get client IP-address
        getIPv4();
	});
       
    async function getComputers () {
        // attempt to get computers that user have access to
        // get computers
        let params={};
        params["perm"]=["COMPUTER_REMOTE"];              
        let cmp=await call_aurora("getComputersByPerm",params);

        await cmp;        

        if (cmp.err == 0) {
            // success - lets get all the metadata parent names of the computers
            params={};
            params[""]=cmp.computeres
            // sort result
            computers=hash2SortedSelect(cmp.computers);            
        }
        if (cmp.err == 0) { return 1; } else { return 0; }       
    }    

    async function getProtocols () {
        // get valid protocols for computer
        prot=undefined;
        protocols=[];
        protocolval="VNC";
        let params={};
        params["id"]=computerval;
        let prt=await call_aurora("getComputerTunnelProtocols",params);      

        await prt;

        if (prt.err == 0) {
            let protocoltable=prt.protocols;
            // make a hash
            protocolhash={};
            protocoltable.forEach((item) => {
                protocolhash[item] = item;
            });
            // sort result
            protocols=hash2SortedSelect(protocolhash);
        }
        if (prt.err == 0) { return 1; } else { return 0; }
    }

    const runGetProtocols = () => {
        prot=getProtocols();
        return "";
    }    

    async function openTunnel () {
        // attempt to open tunnell        
        tunneldata={};
        let params={};
        params["id"]=computerval;              
        params["protocol"]=protocolhash[protocolval];
        params["client"]=ip;
        let tun=await call_aurora("openComputerTunnel",params);

        await tun;

        if (tun.err == 0) {
            // get result
            tunneldata=tun.tunnel; 
            // show tunnel data
            showdata=true;
        }
        if (tun.err == 0) { return 1; } else { return 0; }       

    }

    const runOpenTunnel = () => {
        tunprom=undefined;
        tunprom=openTunnel();
        return "";
    }
    
    // get IP v4 address from internal service
    const getIPv4 = () => {        
        fetch(ipaction,{
            method: "GET",            /* HTTP method */
            credentials: "omit",      /* do not send cookies */              
            mode: "cors",
        })  
        .then(response => response.json())
        .then(data => {
            // we were successful - get result    
            if (data.err == 0) { ip = data["REMOTE_HOST"]; }
        });
    }
</script>

{#if !disabled}
    <div class="ui_title ui_center">Remote Control</div>
    <div class="ui_center">
        <div class="ui_label ui_margin_top">Your IP Address</div>
    <div class="ui_center">{ip}&nbsp;</div>
    {#if ip == "N/A"}
       <div class="ui_label ui_margin_top ui_center">This is not a valid IP-address. Unable to open tunnell...</div>
    {/if}
    </div>
    {#if cmpprom != undefined}
        {#await cmpprom}
            <Status message="Retrieving computers..." type="processing" />
        {:then result}
            {#if result}
                <div class="ui_center">
                    <div class="ui_label ui_margin_top">Computer</div>
                    <div class="ui_input">
                        <InputSearchList bind:value={computerval} datalist={computers} defaultValue={computerval} />
                    </div>
                </div>
            {/if}
        {:catch error}
            <div class="ui_center">Unable to load form data for this page...please try again later...</div>
        {/await}
    {/if}
    {#if computerval != curcomputerval && /^\d+$/.test(computerval) && ip != "N/A"}
            <!-- Another computer was selected, get valid protocols for computer -->
            {runGetProtocols()}
    {/if}
    {#if prot != undefined && /^\d+$/.test(computerval) && ip != "N/A"}
        {#await prot}
            <Status message="Retrieving protocols for computer {computerval}..." type="processing" />
        {:then result}
            {#if result}
                <div class="ui_center">
                    <!-- show protocol list for computer -->
                    <div class="ui_label ui_margin_top">Protocol</div>
                    <div class="ui_input">                        
                        <div class="ui_select">
                            <select bind:value={protocolval}>
                               {#each protocols as typ}                        
                                  <option value={typ.id} selected={(typ.id == protocolval ? true : false)}}>
                                     {typ.text}
                                  </option>
                               {/each}
                            </select>
                         </div>
                    </div>
                    {#if protocolval != "" && protocolhash[protocolval] !== undefined}
                        <!-- show open tunnell button -->
                        <button class="ui_button ui_margin_top" on:click={() => { runOpenTunnel() }}>Open Tunnel</button>
                    {/if}
                    {#if showdata && tunprom != undefined && protocolval != "" && protocolhash[protocolval] !== undefined}
                        {#await tunprom}
                            <Status message="Opening tunnel to computer {computerval} for client {ip}..." type="processing" />
                        {:then result}
                            {#if result}
                                <!-- show tunnel data -->
                                <div class="ui_label ui_margin_top">Connection Info for {protocolhash[protocolval]}</div>
                                {#if protocolhash[protocolval] == "VNC"}
                                    <a href={"./vnc.cgi?host="+tunneldata}>{tunneldata}</a>
                                    <!-- RFC7869 -->
                                    <!-- <a href={"vnc://"+tunneldata}>{tunneldata}</a> -->
                                {:else if protocolhash[protocolval] == "RDP"}
                                    <a href={"./rdp.cgi?host="+tunneldata}>{tunneldata}</a>
                                {:else}
                                    {tunneldata}
                                {/if}
                            {/if}
                        {/await}
                    {/if}
                </div>
            {/if}
        {:catch error}
            <div class="ui_center">Unable to load protocols for computer {computerval}...please try again later...</div>
        {/await}
    {/if}
{:else}
    {window.location.href=CFG["www.base"]}
{/if}

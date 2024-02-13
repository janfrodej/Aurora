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
   import Tabs from './Tabs.svelte';
   import Create from './Create.svelte';
   import Manage from './Manage.svelte';
   import Control from './Control.svelte';
   import Auth from './Auth.svelte';
   import AuroraTree from './AuroraTree.svelte';
   import Modal from "./Modal.svelte"; 
   import Announcement from "./Announcement.svelte";
   import { setCookieValue } from "./_cookies";
   import { route } from "./_stores";
   import Status from "./Status.svelte";

   let showauth = false;   
   let showtree = false;
   let showannounce = false;
   let tabItems = ['Create', 'Manage', 'Control' ];
   let p_logout;

   let routestr = "";
   route.subscribe(value => { routestr = value; });
   const uroute = String(routestr).substring(0,1).toUpperCase()+String(routestr).substring(1,routestr.length);
   let activeItem = (routestr != "" && (routestr == "create" || routestr == "control") ? uroute : "Manage" );
   
    let disabled=false;    
    let CFG={};    

    // handles first time logon attempt
    onMount(async () => {
      // fetch configuration and wait
      CFG =  await getConfig();
      // set disabled
      disabled = CFG["www.maintenance"]||false;
      // attempt an authentication automatically
      // and thereby check our credentials
      // we will be redirected to login-page if it fails
		call_aurora("doAuth",undefined);   
      
      // check if we are loading specific routes
      // and enable them as needed   
      if (routestr == "auth") {
         showauth = true;   
         // reset route since we have routed already
         // we ignore the parameter list because it is not used without a route
         route.set("");      
      } else if (routestr == "create") {         
         // reset route since we have routed already
         // we ignore the parameter list because it is not used without a route
         route.set("");
      } else if (routestr == "control") {
         // reset route since we have routed already
         // we ignore the parameter list because it is not used without a route
         route.set("");
      }      
	 });


    async function logout () {
      // do an actual logout and removal of auth tokens
      p_logout = call_aurora("doDeAuth",undefined,false,false);
      await p_logout;
      // reset cookie information       
      setCookieValue(CFG["www.cookiename"],"authstr","",CFG["www.domain"],CFG["www.cookie.timeout"],"/");               
      // redirect to login page
      window.location.href=CFG["www.base"];   
    }    

   const handleSysMenu = (e) => {
      if (e.target.value == "tree") {         
         // entity tree
         showtree=true;
      } else if (e.target.value == "auth") {
         // auth
         showauth=true;
      } else if (e.target.value == "logout") {
         // logout
         logout();
      } else if (e.target.value == "announcements") {
         // show announcements
         showannounce=true;
      }
      // reset selectedindex to first element   
      // if first menu element is hidden (meaning its not a normal dropdown menu)
      if (((e.target.options != undefined) && (e.target.options["0"].hidden)) ||
          (e.target.parentElement.firstChild.hidden)) {
         // this works for Firefox
         e.target.parentElement.selectedIndex = 0;
         // this works for Chrome
         if (e.target.options != undefined) { e.target.options.selectedIndex = 0; }
      }    
   }

   const closeAuth = () => {
      showauth=false;
   }

   const closeTree = () => {
      showtree=false;
   }

   const closeAnnounce = () => {
      showannounce=false;
   }

</script>

{#if !disabled}
   {#if p_logout != undefined}
      {#await p_logout}            
         <Status message="Logging out..." type="processing" />
      {/await}
   {/if}
   <div class="ui_right ui_margin_right">
      <select name="sysmenu" class="ui_select_special" on:click={(ev) => { handleSysMenu(ev); }}>
         <option value="NONE" hidden={true} selected={true}>&#8801</option>
         <option value="announcements">Announcements</option>
         <option value="auth">Change Authentication</option>
         <option value="tree">Manage Entity Tree</option>         
         <option value="logout">Logout</option>
      </select>
   </div>   

   <Tabs tabItems = {tabItems} bind:activeItem = {activeItem} />
         
   <div class="ui_divider"></div>

   {#if activeItem === 'Create'}
      <Create />
   {:else if activeItem === 'Manage'}
      <Manage />
   {:else if activeItem === 'Control'}
      <Control />       
   {/if}     
   {#if showauth}  
      <Modal width="80" height="90" border={false} closeHandle={() => { closeAuth() }}>      
         <Auth />         
      </Modal>   
   {/if}
   {#if showtree}
      <Modal width="80" height="90" border={false} closeHandle={() => { closeTree() }}>      
         <AuroraTree />
      </Modal>   
   {/if}  
   {#if showannounce}
      <Modal width="80" height="90" border={false} closeHandle={() => { closeAnnounce() }}>      
         <Announcement visibleCount="0" />
      </Modal>   
   {/if}  
{:else}
   <div></div>
{/if}

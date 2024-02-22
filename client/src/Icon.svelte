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
  import { createEventDispatcher } from 'svelte';
  const dispatch = createEventDispatcher();
  // icons have been copied/lent from Google Material UI
  export let size="10";
  export let offset=true;
  export let name="arrowforward";
  export let fill="#000000";
  export let hovering=false;
  export let popuptext="";
  export let margin="0px";
  
  const getSizePx = () => {
    return ""+size+"px";
  }

  const relSizePx = () => {
    if (offset) {
      return ""+Math.floor(((size/3)*-1))+"px";
    } else { return "0px"; }
  }
  
  // send event out of component
  function eHandler(type, data) {     
    // set if mouse is above icon or not at any given 
    // time
    if (type == "mouseover") {
      hovering=true;  
    } else if (type == "mouseout") {
      hovering=false;
    }
    dispatch(type,data);
  }
  </script>

<!-- svelte-ignore a11y-mouse-events-have-key-events -->
<span 
  title={popuptext}
  on:mouseout={(e) => { eHandler("mouseout",e); }}
  on:mouseover={(e) => { eHandler("mouseover",e); } }
  on:click={(e) => { eHandler("click",e); }}
  on:keypress={ (e) => { eHandler("keypress",e); }}
  style={"margin-top: " + margin + ";"}
>
  {#if name == "add"}
  <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M440-280h80v-160h160v-80H520v-160h-80v160H280v80h160v160Zm40 200q-83 0-156-31.5T197-197q-54-54-85.5-127T80-480q0-83 31.5-156T197-763q54-54 127-85.5T480-880q83 0 156 31.5T763-763q54 54 85.5 127T880-480q0 83-31.5 156T763-197q-54 54-127 85.5T480-80Zm0-80q134 0 227-93t93-227q0-134-93-227t-227-93q-134 0-227 93t-93 227q0 134 93 227t227 93Zm0-320Z"/></svg>
  {/if}
  {#if name == "arrowforward"}
    <svg xmlns="http://www.w3.org/2000/svg" enable-background="new 0 0 24 24" height={getSizePx()} viewBox="0 0 24 24" width={getSizePx()} fill="#000000"><g><path d="M0,0h24v24H0V0z" fill="none"/></g><g><polygon points="6.23,20.23 8,22 18,12 8,2 6.23,3.77 14.46,12"/></g></svg>
  {/if}
  {#if name == "arrowback"}
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 0 24 24" width={getSizePx()} fill={fill}><path d="M0 0h24v24H0z" fill="none"/><path d="M11.67 3.87L9.9 2.1 0 12l9.9 9.9 1.77-1.77L3.54 12z"/></svg>  
  {/if}
  {#if name == "arrowup"}
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 0 24 24" width={getSizePx()} fill={fill}><path d="M0 0h24v24H0z" fill="none"/><path d="M12 8l-6 6 1.41 1.41L12 10.83l4.59 4.58L18 14z"/></svg>
  {/if}
  {#if name == "arrowdown"}
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 96 960 960" width={getSizePx()} fill={fill}><path d="M0 0h24v24H0z" fill="none"/><path d="M480 712 240 472l56-56 184 184 184-184 56 56-240 240Z"/></svg>
  {/if}
  {#if name == "close"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="m256-200-56-56 224-224-224-224 56-56 224 224 224-224 56 56-224 224 224 224-56 56-224-224-224 224Z"/></svg>
  {/if}
  {#if name == "delete"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M280-120q-33 0-56.5-23.5T200-200v-520h-40v-80h200v-40h240v40h200v80h-40v520q0 33-23.5 56.5T680-120H280Zm400-600H280v520h400v-520ZM360-280h80v-360h-80v360Zm160 0h80v-360h-80v360ZM280-720v520-520Z"/></svg>
  {/if}
  {#if name == "folder"}
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 0 24 24" width={getSizePx()} fill={fill}><path d="M0 0h24v24H0z" fill="none"/><path d="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"/></svg>    
  {/if}
  {#if name == "file"}
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 0 24 24" width={getSizePx()} fill={fill}><path d="M0 0h24v24H0z" fill="none"/><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>
  {/if}
  {#if name == "folder managed"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="m680-80-12-60q-12-5-22.5-10.5T624-164l-58 18-40-68 46-40q-2-12-2-26t2-26l-46-40 40-68 58 18q11-8 21.5-13.5T668-420l12-60h80l12 60q12 5 22.5 10.5T816-396l58-18 40 68-46 40q2 12 2 26t-2 26l46 40-40 68-58-18q-11 8-21.5 13.5T772-140l-12 60h-80Zm40-120q33 0 56.5-23.5T800-280q0-33-23.5-56.5T720-360q-33 0-56.5 23.5T640-280q0 33 23.5 56.5T720-200Zm-560 40q-33 0-56.5-23.5T80-240v-480q0-33 23.5-56.5T160-800h240l80 80h320q33 0 56.5 23.5T880-640v131q-35-25-76-38t-85-13q-118 0-198.5 82.5T440-281q0 32 7 62t21 59H160Z"/></svg>
  {/if}
  {#if name == "folder off"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M871-202 274-800h114l80 80h332q33 0 56.5 23.5T880-640v400q0 11-2 20.5t-7 17.5ZM819-28 687-160H160q-33 0-56.5-23.5T80-240v-480q0-33 23.5-56.5T160-800l80 80H128L28-820l56-56L876-84l-57 56Z"/></svg>
  {/if}
  {#if name == "harddrive"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M680-320q25 0 42.5-17t17.5-43q0-25-17.5-42.5T680-440q-26 0-43 17.5T620-380q0 26 17 43t43 17ZM80-600l136-136q11-11 25.5-17.5T273-760h413q17 0 31.5 6.5T743-736l137 136H80Zm80 400q-34 0-57-23t-23-57v-240h800v240q0 34-23.5 57T800-200H160Z"/></svg>
  {/if}
  {#if name == "unfoldmore"}
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 0 24 24" width={getSizePx()} fill={fill}><path d="M0 0h24v24H0z" fill="none"/><path d="M12 5.83L15.17 9l1.41-1.41L12 3 7.41 7.59 8.83 9 12 5.83zm0 12.34L8.83 15l-1.41 1.41L12 21l4.59-4.59L15.17 15 12 18.17z"/></svg>
  {/if}
  {#if name == "unfoldless"}
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 0 24 24" width={getSizePx()} fill={fill}><path d="M0 0h24v24H0z" fill="none"/><path d="M7.41 18.59L8.83 20 12 16.83 15.17 20l1.41-1.41L12 14l-4.59 4.59zm9.18-13.18L15.17 4 12 7.17 8.83 4 7.41 5.41 12 10l4.59-4.59z"/></svg>
  {/if}
  {#if name == "error"}    
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 0 24 24" width={getSizePx()} fill={fill}><path d="M24 34q.7 0 1.175-.475.475-.475.475-1.175 0-.7-.475-1.175Q24.7 30.7 24 30.7q-.7 0-1.175.475-.475.475-.475 1.175 0 .7.475 1.175Q23.3 34 24 34Zm-1.35-7.65h3V13.7h-3ZM24 44q-4.1 0-7.75-1.575-3.65-1.575-6.375-4.3-2.725-2.725-4.3-6.375Q4 28.1 4 23.95q0-4.1 1.575-7.75 1.575-3.65 4.3-6.35 2.725-2.7 6.375-4.275Q19.9 4 24.05 4q4.1 0 7.75 1.575 3.65 1.575 6.35 4.275 2.7 2.7 4.275 6.35Q44 19.85 44 24q0 4.1-1.575 7.75-1.575 3.65-4.275 6.375t-6.35 4.3Q28.15 44 24 44Zm.05-3q7.05 0 12-4.975T41 23.95q0-7.05-4.95-12T24 7q-7.05 0-12.025 4.95Q7 16.9 7 24q0 7.05 4.975 12.025Q16.95 41 24.05 41ZM24 24Z"/></svg>
  {/if}    
  {#if name == "plus"}
    <!-- svgrepo.com -->
    <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -6 24 24" width={getSizePx()} fill={fill} stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"><path d="m12.75 7.75h-10m5-5v10"/></svg>
  {/if}    
  {#if name == "star"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill} transform="rotate(180)"><path d="m233-80 65-281L80-550l288-25 112-265 112 265 288 25-218 189 65 281-247-149L233-80Z"/></svg>
  {/if}
  {#if name == "stars"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="m320-240 160-122 160 122-60-198 160-114H544l-64-208-64 208H220l160 114-60 198ZM480-80q-83 0-156-31.5T197-197q-54-54-85.5-127T80-480q0-83 31.5-156T197-763q54-54 127-85.5T480-880q83 0 156 31.5T763-763q54 54 85.5 127T880-480q0 83-31.5 156T763-197q-54 54-127 85.5T480-80Zm0-80q134 0 227-93t93-227q0-134-93-227t-227-93q-134 0-227 93t-93 227q0 134 93 227t227 93Zm0-320Z"/></svg>
  {/if}
  {#if name == "storage"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M120-160v-160h720v160H120Zm80-40h80v-80h-80v80Zm-80-440v-160h720v160H120Zm80-40h80v-80h-80v80Zm-80 280v-160h720v160H120Zm80-40h80v-80h-80v80Z"/></svg>
  {/if}
  {#if name == "template"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M360-240q-33 0-56.5-23.5T280-320v-480q0-33 23.5-56.5T360-880h360q33 0 56.5 23.5T800-800v480q0 33-23.5 56.5T720-240H360ZM200-80q-33 0-56.5-23.5T120-160v-560h80v560h440v80H200Z"/></svg>
  {/if}
  {#if name == "tune"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M440-120v-240h80v80h320v80H520v80h-80Zm-320-80v-80h240v80H120Zm160-160v-80H120v-80h160v-80h80v240h-80Zm160-80v-80h400v80H440Zm160-160v-240h80v80h160v80H680v80h-80Zm-480-80v-80h400v80H120Z"/></svg>
  {/if}
  {#if name == "automated"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M480-120q-75 0-140.5-28.5t-114-77q-48.5-48.5-77-114T120-480q0-75 28.5-140.5t77-114q48.5-48.5 114-77T480-840q82 0 155.5 35T760-706v-94h80v240H600v-80h110q-41-56-101-88t-129-32q-117 0-198.5 81.5T200-480q0 117 81.5 198.5T480-200q105 0 183.5-68T756-440h82q-15 137-117.5 228.5T480-120Zm112-192L440-464v-216h80v184l128 128-56 56Z"/></svg>
  {/if}
  {#if name == "manual"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M791-55 671-175q-42 26-90 40.5T480-120q-75 0-140.5-28.5t-114-77q-48.5-48.5-77-114T120-480q0-53 14.5-101t40.5-90L55-791l57-57 736 736-57 57ZM480-200q36 0 69.5-8.5T613-233L233-613q-16 30-24.5 63.5T200-480q0 117 81.5 198.5T480-200Zm120-360v-80h110q-41-56-101-88t-129-32q-36 0-69.5 8.5T347-727l-58-58q42-26 90-40.5T480-840q82 0 155.5 35T760-706v-94h80v240H600Zm-80 6-80-80v-46h80v126Zm265 265-58-58q11-22 18.5-45t10.5-48h82q-5 42-18.5 80T785-289Z"/></svg>
  {/if}
  {#if name == "lock open"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M240-640h360v-80q0-50-35-85t-85-35q-50 0-85 35t-35 85h-80q0-83 58.5-141.5T480-920q83 0 141.5 58.5T680-720v80h40q33 0 56.5 23.5T800-560v400q0 33-23.5 56.5T720-80H240q-33 0-56.5-23.5T160-160v-400q0-33 23.5-56.5T240-640Zm240 360q33 0 56.5-23.5T560-360q0-33-23.5-56.5T480-440q-33 0-56.5 23.5T400-360q0 33 23.5 56.5T480-280Z"/></svg>
  {/if}
  {#if name == "lock closed"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M240-80q-33 0-56.5-23.5T160-160v-400q0-33 23.5-56.5T240-640h40v-80q0-83 58.5-141.5T480-920q83 0 141.5 58.5T680-720v80h40q33 0 56.5 23.5T800-560v400q0 33-23.5 56.5T720-80H240Zm240-200q33 0 56.5-23.5T560-360q0-33-23.5-56.5T480-440q-33 0-56.5 23.5T400-360q0 33 23.5 56.5T480-280ZM360-640h240v-80q0-50-35-85t-85-35q-50 0-85 35t-35 85v80Z"/></svg>
  {/if}
  {#if name == "play"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M320-200v-560l440 280-440 280Zm80-280Zm0 134 210-134-210-134v268Z"/></svg>
  {/if}
  {#if name == "refresh"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M480-160q-134 0-227-93t-93-227q0-134 93-227t227-93q69 0 132 28.5T720-690v-110h80v280H520v-80h168q-32-56-87.5-88T480-720q-100 0-170 70t-70 170q0 100 70 170t170 70q77 0 139-44t87-116h84q-28 106-114 173t-196 67Z"/></svg>
  {/if}
  {#if name == "reply"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M760-200v-160q0-50-35-85t-85-35H273l144 144-57 56-240-240 240-240 57 56-144 144h367q83 0 141.5 58.5T840-360v160h-80Z"/></svg>
  {/if}
  {#if name == "save"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M840-680v480q0 33-23.5 56.5T760-120H200q-33 0-56.5-23.5T120-200v-560q0-33 23.5-56.5T200-840h480l160 160Zm-80 34L646-760H200v560h560v-446ZM480-240q50 0 85-35t35-85q0-50-35-85t-85-35q-50 0-85 35t-35 85q0 50 35 85t85 35ZM240-560h360v-160H240v160Zm-40-86v446-560 114Z"/></svg>
  {/if}
  {#if name == "send"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M120-160v-640l760 320-760 320Zm80-120 474-200-474-200v140l240 60-240 60v140Zm0 0v-400 400Z"/></svg>
  {/if}
  {#if name == "stop"}
     <svg xmlns="http://www.w3.org/2000/svg" height={getSizePx()} viewBox="0 -960 960 960" width={getSizePx()} fill={fill}><path d="M320-640v320-320Zm-80 400v-480h480v480H240Zm80-80h320v-320H320v320Z"/></svg>
  {/if}
</span>

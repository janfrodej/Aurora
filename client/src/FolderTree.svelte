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
    import { unixtime2ISO } from "./_iso8601";
    import { sortArray } from "./_tools";

    export let data;
    export let path="/";
    export let selected={};    
</script>

<!-- recurse through a listDatasetFolder hash -->
<div class="ui_left">

<ul>
{#each sortArray(Object.keys(data)) as key,index}
    {#if (((path == "/") || (path == "")) && index == 0)}    
        <li><label><input type="checkbox" value="/" bind:checked={selected["/"]}>/ (ALL OF DATASET)</label></li>        
    {/if}
    <ul>                
        <!-- only recurse to next sub-level if the name is not like "." (self)  -->
        {#if (typeof data[key] === 'object') && key != "."}
            <svelte:self data={data[key]} bind:selected={selected} path={(path == "/" ? path+key : path+"/"+key)} />
        {:else if data[key].type == "D"}
            <!-- only display folders -->
            <li><label><input type="checkbox" value={path} bind:checked={selected[path]}>{data[key].name} ({unixtime2ISO(data[key].mtime)})</label></li>
        {/if}
    </ul>
{/each}
</ul>
</div>

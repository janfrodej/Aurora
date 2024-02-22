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
    // this component gently "stolen" from https://progressivewebninja.com/create-a-svelte-reusable-tab-component/
    import { createEventDispatcher } from 'svelte';
    const dispatch = createEventDispatcher();

    export let tabItems;
    export let activeItem;
    export let color="#555";
    export let highlightcolor="#d91b42";

    const changeActiveItem = (item) => {
        activeItem = item;
    };
</script>

<div class="tabs">
    <ul>
        {#each tabItems as item}
            <!-- svelte-ignore a11y-click-events-have-key-events -->
            <li style="color: {color};" on:click={() => changeActiveItem(item)}>
                {#if item === activeItem}
                    <div class="active" style="color: {highlightcolor};">{item}</div>
                {:else}
                    <div>{item}</div>
                {/if}
            </li>
        {/each}
    </ul>
</div>

<style>
    .tabs {
        float: center;
        clear:left;
        /* margin-bottom: 40px;        */
    }
    ul {
        clear: left;
        display: flex;
        justify-content: center;
        padding: 0;
        list-style-type: none;
    }
    li {        
        margin: 0px 16px;
        font-size: 18px;      
        cursor: pointer;
    }
    .active {              
        border-bottom: 2px solid;
        padding-bottom: 8px;
    }

</style>

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

    Description: Show the privacy message of AURORA.
-->
<script>
    import Modal from "./Modal.svelte";    
    import { getConfig } from "./_config";
    import { getCookieValue, setCookieValue } from "./_cookies";
    import { onMount } from "svelte";

    // variables
    export let showbanner = true;
    export let show = false;
    export let closeHandler;
    let CFG = {};

    onMount(async () => {
        // fetch configuration and wait
        CFG =  await getConfig();        
        // read cookie info
        let privacy=getCookieValue(CFG["www.cookiename"],"privacy");
        privacy = (privacy == undefined ? true : (privacy == "false" ? false : true));
        if (!privacy) { showbanner = false; }
    });    

    const showPrivacy = () => {        
        show  = true;
    }

    const closePrivacy = () => {
        show = false;
        if (closeHandler != undefined) { closeHandler(); }
    };

    const disablePrivacy = () => {        
        let privacy = false;
        setCookieValue(CFG["www.cookiename"],"privacy",privacy,CFG["www.domain"],CFG["www.cookie.timeout"]);
        showbanner = false;
    };

</script>

{#if showbanner}
    <div class="privacy_banner">
        <div class="privacy_banner_text">                            
            Read more about how AURORA gathers and utilizes personal information, why and how it uses cookies and about your privacy rights.
            <button class="privacy_button" on:click={() => { showPrivacy() }}>Read</button> 
            <button class="privacy_button ui_margin_left" on:click={() => { disablePrivacy() }}>I Understand</button>
        </div>
    </div>
{/if}    
{#if show}
    <Modal width="80" height="90" border={false} closeHandle={() => { closePrivacy() }}>
        <div class="ui_title">AURORA Privacy Statement</div>
        <div class="privacy_paragraph">
            This is a privacy statement and overview for AURORA on what personal information it uses, how it is handled, 
            who is responsible for the handling and which rights you have and who to contact about your personal information. 
            It also gives you an overview of what information are stored in cookies, what the aim of that storage is and who is handling that information.
        </div>
            
        <div class="privacy_paragraph">
            When you use the AURORA-system you accept that cookies are being stored in your browser. If you do not accept this, you have 
            to adjust the settings of your browser to deny or revoke this acceptance. Please note, that if you do revoke cookies for this site 
            it will be impossible to use the AURORA web client.
        </div>
            
        <div class="privacy_section_header">PERSONAL INFORMATION</div>
            
        <div class="privacy_paragraph">
            Personal information are all forms of data, information, assessments that can be used to identify you as an individual. It can be 
            things like an email address, name, phone number, address etc (or any combination of these). The deciding criteria for what is 
            personal information is if this information can directly or indirectly identify an actual individual.
        </div>
            
        <div class="privacy_section_header">COOKIES</div>
            
        <div class="privacy_paragraph">
            Cookies are small information packages that are stored by the browsers locally on your computer and can be accessed by the site that 
            created them. Any kind of information can be stored in a cookie, but these are the purposes of cookie in AURORA:
            <ul>
                <li>To store login information. This is related to who logged in to the AURORA web-client as a random string or id. Because it is a 
            random identifier it is anonymized in the web browser and locally on the computer, but this information can be used internally on 
            the AURORA-server to identify who this session information is related to.</li>
                <li>Session information. This is session data (such as search settings, accepting this privacy notification and so on). All of this 
            information is anonymous and cannot definitely identify any given user or individual (only in combination with the random string or 
            id mentioned previously).</li>
            </ul>
            No information in relation to these cookies are fed into Google Analytics or similar analytical and/or tracking solutions.
        </div>
            
        <div class="privacy_section_header">PURPOSE</div>
            
        <div class="privacy_paragraph">
            The purpose of storing personal information is because in order for AURORA to do its work it needs to know who has logged into 
            the system using a universal identifier, which happens to be the users email address. In addition it needs to know the full name 
            of that email address. Without this information it is impossible to give users access to creating datasets and managing them or 
            offering any kind of security related features.
        </div>
            
        <div class="privacy_section_header">INFORMATION USED</div>
            
        <div class="privacy_paragraph">The full overview of information used and how are as follows:
            <ul>
                <li>Email address and full name in order to identify individual users in the system and allow for management- and security 
            related features. Please also note that email and full name are available to any user with access to AURORA, because it is needed to 
            be so in order to allow for any kind of management. This is also the case for users of AURORA that comes from external entities outside 
            the organization. The information about the users name and email address are open information inside the system, similar to most 
            operating systems.</li>
                <li>Local login-services' username. AURORA can utilize several forms of login services and one such is the OAuth SSO-scheme. In such 
            cases it might be that the various login services store information about the user that is related to its user identity on 
            local systems where the user works or access. This information is tracable to the users email- and full name.</li>
                <li>Textual name or other personal information (such as email) about the user might be stored in a datasets metadata in order to 
            identify who contributed to it, created it and so on. This is considered fair use within the AURORA-system. This metadata can be changed and 
            updated by the administrators and creators of the datasets. This information, such as full name, might also not uniquely identify anyone 
            (eg. many may have the same name) and are not attached to any user accounts within AURORA itself. We also store user identity id of the user that 
            created a dataset which cannot be changed. This id points to the user account in AURORA and can be used to definetly identify the creator. However, 
            as soon as that users account has been deactived or removed from AURORA we no longer know who that id points to. So in other words, this id will 
            only be usable for the duration of the users relation with AURORA.</li>
                <li>Logging of all tunnels opened to control COMPUTER-entities. These logs contains the user identity of who created the tunnel. This information 
            is kept in order to have the ability to track any security breaches or concerns. It will also be generated usage statistics based on these tunnels in 
            order to have an overview of the use in the system as a whole. None of these aggregated information is able to identify any particular user and can 
            be kept indefinetly. These logs are wiped with regular interval, removing eg. logs that are older than 3 months.</li>
                <li>Logging of all tunnels opened to control COMPUTER-entities. These logs contains the user identity of who created the tunnel. This information 
            is kept in order to have the ability to track any security breaches or concerns. It will also be generated usage statistics based on these tunnels in 
            order to have an overview of the use in the system as a whole. None of these aggregated information is able to identify any particular user and can 
            be kept indefinetly. These logs are wiped with regular interval, removing eg. logs that are older than 3 months.</li>    
            </ul>
        </div>
            
        <div class="privacy_section_header">STORAGE DURATION</div>
            
        <div class="privacy_paragraph">The data in the AURORA-system are stored for the following durations:
            <ul>
                <li>Email and full name are stored as long as the user is using the system, still has a relationship with the organization offering the 
            AURORA-system and have not requested to be anonymized (please note that complete anonymization might not be possible or required by 
            the organization). If the user looses his or her relationship with the organization or stops using the AURORA-system (in the case of 
            no relationship), the account information will be anonymized/wiped within a year afterwards. No user-accounts in AURORA are deleted, 
            the personal information is removed/anonymized.</li>
                <li>Login- and session information are stored as long as the browser keeps the information updated or the user keeps updating its 
            content by using the AURORA-system. The server-side session information of AURORA are usually only kept for a short amount of time, no 
            longer than two weeks until the server-side cache times out and/or are deleted. Please also note that the server-side session information 
            is anonymized upon logging out and then it becomes impossible to trace the session information to a specific user.</li>
                <li>Metadata information about datasets are kept indefinitely because of management-, usage- and statistics purposes, even after the 
            dataset has been deleted. Please note, however, that as long as the metadata does not contain any personal information, it is not 
            tracable to any individual user, if the user who created it has had his or her account anonymized. The link between a dataset and a 
            users account is in the form of a numbered identifier and as soon as the USER-account has been anonymized, it is impossible to know 
            exactly who created that dataset (barring metadata identifiers). The dataset will, however, be tracable to the AURORA-group where the 
            dataset was created and if any user in that group remembers who created it, then that is not within the powers of the AURORA-system 
            and/or its administrators, algorithms, procedures or design to deal with (try calling the MIB).</li>
                <li>Tunnel-logs are kept for 3 months.</li>
                <li>Connection-logs are kept for 3 months.</li>
            </ul>
        </div>
            
        <div class="privacy_section_header">LEGAL BASIS</div>
            
        <div class="privacy_paragraph">
            The legal basis for processing your information in AURORA is the EU GDPR and the Norwegian law based upon the GDPR 
            (Personopplysningsloven). Of specific support is the Personopplysningsloven &#167;6 and &#167;8, which clearly states that 
            the processing of personal informations is acceptable as long as necessary for work related functions and/or for research- and 
            scientific purposes of public interest.
        </div>
            
        <div class="privacy_section_header">YOUR RIGHTS</div>
            
        <div class="privacy_subsection_header">THE RIGHT TO TRANSPARENCY</div>
            
        <div class="privacy_paragraph">
            You can contact the AURORA administrators and ask to know which personal information that the system are processing about you,
            where they come from and why it has them. You can also ask for a copy of this information. You cannot ask for this same information 
            about other people than yourself.
        </div>
            
        <div class="privacy_subsection_header">THE RIGHT TO DEMAND CORRECTION</div>
            
        <div class="privacy_paragraph">
            If you, after gaining access to your personal information used by AURORA, discover incorrect, incomplete or inaccurate information, you
            can ask to have it corrected.
        </div>
            
        <div class="privacy_subsection_header">THE RIGHT TO BE DELETED/FORGOTTEN</div>

        <div class="privacy_paragraph">
            AURORA have procedures for removing user information upon a user ending his or hers relationship to the organization or stops using the 
            system. However, you can still ask for your information to be deleted. As the user-information is not vital for the long term storage of 
            the datasets, we will usually accept your information being removed. This entails anonymizing the information stored in the user-account, as 
            we cannot remove the account itself of design and usage reasons. After anonymizing the account, the datasets that you created cannot any longer 
            be traced to any personal information within them. Note, however, as we covered in the section "Storage Duration" that some of your personal 
            information might be stored in the datasets metadata and are considered fair use. 
        </div>
            
        <div class="privacy_paragraph">
            Also if we have the right according to law, or a law denies us to remove this information, or you do not have any substantial reason to demand 
            the total deletion of personal information (beyond the user account), we can still retain this information within the system.
        </div>
            
        <div class="privacy_subsection_header">THE RIGHT TO LIMITED PROCESSING</div>
            
        <div class="privacy_paragraph">
            You can demand that we temporarily suspend the use of your personal information. You can demand this if the information we 
            have about you is inaccurate or we do not have sufficient reason to process it. We will then stop the processing until we 
            have investigated your injections.
        </div>
            
        <div class="privacy_subsection_header">THE RIGHT TO INFORMATION PORTABILITY</div>
            
        <div class="privacy_paragraph">
            If the AURORA or the organization processes your personal information based on your 
            consent or an agreement we have with you, and the treatment is transferred automatically 
            (eg. that the data is calculated automatically or machines analyze the information), you can
            demand that we transfer several of your personal details to you or to a third party.
        </div>
            
        <div class="privacy_subsection_header">THE RIGHT TO PROTEST</div>
            
        <div class="privacy_paragraph">
            If you are in a unique situation where the processing of personal information by AURORA creates special challenges to you, you can protest 
            the processing. If your interests weighs heavier than the usage by the organization, AURORA will not process your personal information 
            any longer.
        </div>
            
        <div class="privacy_section_header">CONTACT</div>
            
        <div class="privacy_subsection_header">Please go to this address to find out more about who to ask about privacy issues:</div>
            
        <div class="privacy_paragraph"><a href={CFG["privacy.www.questions"]} target="_blank">Questions</a></div>
            
        <div class="privacy_subsection_header">Please go to this address to find out more about the privacy ombud:</div>
            
        <div class="privacy_paragraph"><a href={CFG["privacy.www.ombud"]} target="_blank">Ombud</a></div>    
    </Modal>
{/if}

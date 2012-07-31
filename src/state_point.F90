module state_point

  use error,  only: warning, fatal_error
  use global
  use output, only: write_message, print_batch_keff
  use string, only: to_str

  implicit none

contains

!===============================================================================
! CREATE_STATE_POINT creates a state point binary file that can be used for
! restarting a run
!===============================================================================

  subroutine create_state_point()

    integer :: i ! loop index

    ! Set filename for binary state point
    path_state_point = 'restart.' // trim(to_str(current_batch)) // '.binary'

    ! Write message
    message = "Creating state point " // trim(path_state_point) // "..."
    call write_message()

    ! Open binary state point file for writing
    open(UNIT=UNIT_STATE, FILE=path_state_point, STATUS='replace', &
         ACCESS='stream')

    ! Write revision number for state point file
    write(UNIT_STATE) REVISION_STATEPOINT
    
    ! Write OpenMC version
    write(UNIT_STATE) VERSION_MAJOR, VERSION_MINOR, VERSION_RELEASE

    ! Write out random number seed
    write(UNIT_STATE) seed

    ! Write run information
    write(UNIT_STATE) run_mode, n_particles, n_batches, &
         n_inactive, gen_per_batch

    ! Write out current batch number
    write(UNIT_STATE) current_batch

    ! Write out keff and entropy for each batch
    if (run_mode == MODE_CRITICALITY) then
       write(UNIT_STATE) k_batch(1:current_batch)
       if (entropy_on) write(UNIT_STATE) entropy(1:current_batch)
    end if

    ! Write out global tallies sum and sum_sq
    write(UNIT_STATE) N_GLOBAL_TALLIES
    write(UNIT_STATE) global_tallies(:) % sum
    write(UNIT_STATE) global_tallies(:) % sum_sq

    ! Write out tallies sum and sum_sq
    if (tallies_on) then
       write(UNIT_STATE) n_tallies
       do i = 1, n_tallies
          write(UNIT_STATE) size(tallies(i) % scores, 1)
          write(UNIT_STATE) size(tallies(i) % scores, 2)
          write(UNIT_STATE) tallies(i) % scores(:,:) % sum
          write(UNIT_STATE) tallies(i) % scores(:,:) % sum_sq
       end do
    end if

    ! Close binary state point file
    close(UNIT_STATE)

  end subroutine create_state_point

!===============================================================================
! LOAD_STATE_POINT
!===============================================================================

  subroutine load_state_point()

    integer :: i       ! loop index
    integer :: temp(3) ! temporary variable

    ! Write message
    message = "Loading state point " // trim(path_state_point) // "..."
    call write_message(1)

    ! Open binary state point file for writing
    open(UNIT=UNIT_STATE, FILE=path_state_point, STATUS='old', &
         ACCESS='stream')

    ! Raad revision number for state point file and make sure it matches with
    ! current version
    read(UNIT_STATE) temp(1)
    if (temp(1) /= REVISION_STATEPOINT) then
       message = "State point binary version does not match current version " &
            // "in OpenMC."
       call fatal_error()
    end if
    
    ! Read OpenMC version
    read(UNIT_STATE) temp(1:3)
    if (temp(1) /= VERSION_MAJOR .or. temp(2) /= VERSION_MINOR &
         .or. temp(3) /= VERSION_RELEASE) then
       message = "State point file was created with a different version " // &
            "of OpenMC."
       call warning()
    end if

    ! Read and overwrite random number seed
    read(UNIT_STATE) seed

    ! Read and overwrite run information
    read(UNIT_STATE) run_mode, n_particles, n_batches, &
         n_inactive, gen_per_batch

    ! Read batch number to restart at
    read(UNIT_STATE) restart_batch

    ! Read keff and entropy for each batch
    if (run_mode == MODE_CRITICALITY) then
       read(UNIT_STATE) k_batch(1:restart_batch)
       if (entropy_on) read(UNIT_STATE) entropy(1:restart_batch)
    end if

    if (master) then
       ! Read number of global tallies and make sure it matches
       read(UNIT_STATE) temp(1)
       if (temp(1) /= N_GLOBAL_TALLIES) then
          message = "Number of global tallies does not match in state point."
          call fatal_error()
       end if

       ! Read global tally data
       read(UNIT_STATE) global_tallies(:) % sum
       read(UNIT_STATE) global_tallies(:) % sum_sq

       ! Read tally data 
       if (current_batch > n_inactive) then
          ! Read number of tallies and make sure it matches
          read(UNIT_STATE) temp(1)
          if (temp(1) /= n_tallies) then
             message = "Number of tallies does not match in state point."
             call fatal_error()
          end if

          do i = 1, n_tallies
             ! Make sure dimensions match for tally filters and scores
             read(UNIT_STATE) temp(1:2)
             if (temp(1) /= size(tallies(i) % scores, 1) .or. &
                  temp(2) /= size(tallies(i) % scores, 2)) then
                message = "Tally dimensions do not match in state point."
                call fatal_error()
             end if

             ! Read sum and sum squared
             read(UNIT_STATE) tallies(i) % scores(:,:) % sum
             read(UNIT_STATE) tallies(i) % scores(:,:) % sum_sq
          end do
       end if
    end if

    ! Close binary state point file
    close(UNIT_STATE)

  end subroutine load_state_point

!===============================================================================
! REPLAY_BATCH_HISTORY
!===============================================================================

  subroutine replay_batch_history

    real(8), save :: temp(2) = ZERO

    ! Write message at beginning
    if (current_batch == 1) then
       message = "Replaying history from state point..."
       call write_message(1)
    end if

    ! For criticality calculations, turn on tallies if we've reached active
    ! batches
    if (current_batch == n_inactive) tallies_on = .true.

    ! Add to number of realizations
    if (current_batch > n_inactive) then
       n_realizations = n_realizations + 1

       temp(1) = temp(1) + k_batch(current_batch)
       temp(2) = temp(2) + k_batch(current_batch)*k_batch(current_batch)

       keff = temp(1) / n_realizations
       keff_std = sqrt((temp(2)/n_realizations - keff*keff) &
            / (n_realizations - 1))
    end if

    ! print out batch keff
    call print_batch_keff()

    ! Write message at end
    if (current_batch == restart_batch) then
       message = "Resuming simulation..."
       call write_message(1)
    end if

  end subroutine replay_batch_history

end module state_point
# Copyright (c) 2014 SiegeLord
#
# This software is provided 'as-is', without any express or implied
# warranty. In no event will the authors be held liable for any damages
# arising from the use of this software.
#
# Permission is granted to anyone to use this software for any purpose,
# including commercial applications, and to alter it and redistribute it
# freely, subject to the following restrictions:
#
#    1. The origin of this software must not be misrepresented; you must not
#    claim that you wrote the original software. If you use this software
#    in a product, an acknowledgment in the product documentation would be
#    appreciated but is not required.
#
#    2. Altered source versions must be plainly marked as such, and must not be
#    misrepresented as being the original software.
#
#    3. This notice may not be removed or altered from any source
#    distribution.

# Defines a few macros, variables and a function to help with compiling Rust
# programs/libraries and documentation with CMake.
#
# This file utilizes several global variables:
#
# RUSTC_EXECUTABLE - Filename of the rustc executable. You can fill it in using the Findrustc package.
# RUSTDOC_EXECUTABLE - Filename of the rustc executable. You can fill it in using the Findrustdoc package.
# RUSTC_FLAGS - These get passed to rustc.
# RUSTDOC_FLAGS - These flags get passed to rustdoc.

include(CMakeParseArguments)

if(NOT RUSTC_FLAGS)
	set(RUSTC_FLAGS "" CACHE STRING "Flags to pass to the Rust compiler.")
endif()
mark_as_advanced(RUSTC_FLAGS)

if(NOT RUSTDOC_FLAGS)
	set(RUSTDOC_FLAGS "" CACHE STRING "Flags to pass to Rustdoc.")
endif()
mark_as_advanced(RUSTDOC_FLAGS)

# Fetches the dependencies of a Rust crate with local crate root located at
# local_root_file and places them into out_var. Optionally also builds the crate.
#
# Optional arguments:
# OTHER_RUSTC_FLAGS flags - Other flags to pass to rustc.
# DESTINATION destination - If compiling, where to place the compilation artifacts.
# COMPILE - Whether or not to produce artifacts (it won't by default).
#           NOTE! This will force the compillation of this crate every time the
#           project is reconfigured, so use with care!
#
# NOTE: Only the first target's dependencies are fetched!
function(get_rust_deps local_root_file out_var)
	cmake_parse_arguments("OPT" "COMPILE" "DESTINATION" "OTHER_RUSTC_FLAGS" ${ARGN})

	set(root_file "${CMAKE_CURRENT_SOURCE_DIR}/${local_root_file}")

	set(dep_dir "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/.cmake_rust_dependencies")
	file(MAKE_DIRECTORY "${dep_dir}")

	if(OPT_COMPILE)
		file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}")
		set(flags --out-dir "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}")
		message(STATUS "Compiling and getting Rust dependency info for crate root ${local_root_file}")
	else()
		set(flags --no-analysis)
		message(STATUS "Getting Rust dependency info for crate root ${local_root_file}")
	endif()

	execute_process(COMMAND ${RUSTC_EXECUTABLE} ${RUSTC_FLAGS} ${OPT_OTHER_RUSTC_FLAGS} ${flags} --dep-info "${dep_dir}/deps" "${root_file}")

	# Read and parse the dependency information
	file(READ "${dep_dir}/deps" crate_deps)
	file(REMOVE "${dep_dir}/deps")
	string(REGEX REPLACE ".*: (.*)" "\\1" crate_deps "${crate_deps}")
	string(STRIP "${crate_deps}" crate_deps)
	string(REPLACE " " ";" crate_deps "${crate_deps}")

	# Make the dependencies be relative to the source directory
	set(crate_deps_relative "")
	foreach(var IN ITEMS ${crate_deps})
		file(TO_CMAKE_PATH "${var}" var)
		file(RELATIVE_PATH var "${CMAKE_CURRENT_SOURCE_DIR}" "${var}")
		list(APPEND crate_deps_relative "${var}")
		# Hack to re-run CMake if the file changes
		configure_file("${var}" "${dep_dir}/${var}" COPYONLY)
	endforeach()

	set(${out_var} "${crate_deps_relative}" PARENT_SCOPE)
endfunction()

# Adds a target to build a rust crate with the crate root located at local_root_file.
# The compilation output is placed inside DESTINATION within the build directory.
#
# Please pass the crate dependencies obtained through get_rust_deps to the dependencies argument in
# addition to other targets/files you want this target to depend on.
#
# Optional arguments:
#
# ALL - Pass this to make this crate be built by default.
# DESTINATION dest - Where to place the compilation artifacts.
# TARGET_NAME target - Target name for the command to build this crate.
# DEPENDS depends - List of dependencies of this crate.
# OTHER_RUSTC_FLAGS flags - Other flags to pass to rustc.
#
# This function sets two variables:
#
# ${target_name}_FULL_TARGET - This is what you would use as a set of dependencies
#                              for other targets when you want them to depend on the
#                              output of this target.
#
# ${target_name}_ARTIFACTS -   The actual files generated by this command.
#                              You'd use this as a set of files to install/copy elsewhere.
function(rust_crate local_root_file)
	cmake_parse_arguments("OPT" "ALL" "DESTINATION;TARGET_NAME" "DEPENDS;OTHER_RUSTC_FLAGS" ${ARGN})

	if(NOT OPT_TARGET_NAME)
		set(OPT_TARGET_NAME CRATE)
	endif()

	if(OPT_ALL)
		set(ALL_ARG "ALL")
	else()
		set(ALL_ARG "")
	endif()

	set(root_file "${CMAKE_CURRENT_SOURCE_DIR}/${local_root_file}")

	execute_process(COMMAND ${RUSTC_EXECUTABLE} ${RUSTC_FLAGS} ${OPT_OTHER_RUSTC_FLAGS} --print-file-name "${root_file}"
	                OUTPUT_VARIABLE rel_crate_filenames
	                OUTPUT_STRIP_TRAILING_WHITESPACE)

	# Split up the names into a list
	string(REGEX MATCHALL "[^\n\r]+" rel_crate_filenames "${rel_crate_filenames}")

	set(comment "Building ")
	set(crate_filenames "")
	set(first TRUE)
	foreach(name IN ITEMS ${rel_crate_filenames})
		if(${first})
			set(first FALSE)
		else()
			set(comment "${comment}, ")
		endif()
		set(comment "${comment}${OPT_DESTINATION}/${name}")
		list(APPEND crate_filenames "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}/${name}")
	endforeach()
	file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}")

	add_custom_command(OUTPUT ${crate_filenames}
	                   COMMAND ${RUSTC_EXECUTABLE} ${RUSTC_FLAGS} ${OPT_OTHER_RUSTC_FLAGS} --out-dir "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}" "${root_file}"
	                   DEPENDS ${crate_deps_list}
	                   DEPENDS ${OPT_DEPENDS}
	                   COMMENT "${comment}")

	add_custom_target("${OPT_TARGET_NAME}"
	                  ${ALL_ARG}
	                  DEPENDS ${crate_filenames})

	set("${OPT_TARGET_NAME}_ARTIFACTS" "${crate_filenames}" PARENT_SCOPE)
	# CMake Bug #10082
	set("${OPT_TARGET_NAME}_FULL_TARGET" "${OPT_TARGET_NAME};${crate_filenames}" PARENT_SCOPE)
endfunction()

# Like rust_crate, but fetches the crate dependencies for you. This is convenient
# but inefficient if you want to compile the crate several times with different
# configurations (e.g. with --test and without) or if you want to build documentation.
#
# Optional arguments:
#
# ALL - Pass this to make this crate be built by default.
# DESTINATION dest - Where to place the compilation artifacts.
# TARGET_NAME target - Target name for the command to build this crate.
# DEPENDS depends - List of dependencies of this crate.
# OTHER_RUSTC_FLAGS flags - Other flags to pass to rustc.
#
# This function sets two variables:
#
# ${target_name}_FULL_TARGET - This is what you would use as a set of dependencies
#                              for other targets when you want them to depend on the
#                              output of this target.
#
# ${target_name}_ARTIFACTS - The actual files generated by this command.
#                            You'd use this as a set of files to install/copy elsewhere.
function(rust_crate_auto local_root_file)
	cmake_parse_arguments("OPT" "ALL" "DESTINATION;TARGET_NAME" "DEPENDS;OTHER_RUSTC_FLAGS" ${ARGN})

	if(NOT OPT_TARGET_NAME)
		set(OPT_TARGET_NAME CRATE)
	endif()

	if(OPT_ALL)
		set(ALL_ARG "ALL")
	else()
		set(ALL_ARG "")
	endif()

	get_rust_deps(${local_root_file} crate_deps_list
	              OTHER_RUSTC_FLAGS ${OPT_OTHER_RUSTC_FLAGS})

	rust_crate("${local_root_file}"
	           ${ALL_ARG}
	           TARGET_NAME "${OPT_TARGET_NAME}"
	           DESTINATION "${OPT_DESTINATION}"
	           DEPENDS "${crate_deps_list};${OPT_DEPENDS}"
	           OTHER_RUSTC_FLAGS ${OPT_OTHER_RUSTC_FLAGS})
	set("${OPT_TARGET_NAME}_ARTIFACTS" "${${OPT_TARGET_NAME}_ARTIFACTS}" PARENT_SCOPE)
	set("${OPT_TARGET_NAME}_FULL_TARGET" "${${OPT_TARGET_NAME}_FULL_TARGET}" PARENT_SCOPE)
endfunction(rust_crate_auto)

# Like rust_crate, but this time it generates documentation using rust_doc.
#
# Optional arguments:
#
# ALL - Pass this to make this crate be built by default.
# DESTINATION dest - Where to place the compilation artifacts.
# TARGET_NAME target - Target name for the command to build this crate.
# DEPENDS depends - List of dependencies of this crate.
# OTHER_RUSTC_FLAGS flags - Other flags to pass to rustc.
# OTHER_RUSTDOC_FLAGS flags - Other flags to pass to rustdoc.
#
# This function sets two variables:
#
# ${target_name}_FULL_TARGET - This is what you would use as a set of dependencies
#                              for other targets when you want them to depend on the
#                              output of this target.
#
# ${target_name}_ARTIFACTS - The actual files generated by this command.
#                            You'd use this as a set of files to install/copy elsewhere.
function(rust_doc local_root_file)
	cmake_parse_arguments("OPT" "ALL" "DESTINATION;TARGET_NAME" "DEPENDS;OTHER_RUSTDOC_FLAGS;OTHER_RUSTC_FLAGS" ${ARGN})

	if(NOT OPT_TARGET_NAME)
		set(OPT_TARGET_NAME DOC)
	endif()

	if(OPT_ALL)
		set(ALL_ARG "ALL")
	else()
		set(ALL_ARG "")
	endif()

	set(root_file "${CMAKE_CURRENT_SOURCE_DIR}/${local_root_file}")

	execute_process(COMMAND ${RUSTC_EXECUTABLE} ${RUSTC_FLAGS} ${OPT_OTHER_RUSTC_FLAGS} --print-crate-name "${root_file}"
	                OUTPUT_VARIABLE crate_name
	                OUTPUT_STRIP_TRAILING_WHITESPACE)

	set(doc_dir "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}/${crate_name}")
	set(src_dir "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}/src/${crate_name}")
	file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}")

	add_custom_command(OUTPUT "${doc_dir}/index.html" "${doc_dir}" "${src_dir}"
	                   COMMAND ${RUSTDOC_EXECUTABLE} ${RUSTDOC_FLAGS} ${OPT_OTHER_RUSTDOC_FLAGS} -o "${CMAKE_CURRENT_BINARY_DIR}/${OPT_DESTINATION}" "${root_file}"
	                   DEPENDS ${crate_deps_list}
	                   DEPENDS ${OPT_DEPENDS})

	add_custom_target("${OPT_TARGET_NAME}"
	                  ${ALL_ARG}
	                  DEPENDS "${doc_dir}/index.html")

	set("${OPT_TARGET_NAME}_ARTIFACTS" "${doc_dir};${src_dir}" PARENT_SCOPE)
	# CMake Bug #10082
	set("${OPT_TARGET_NAME}_FULL_TARGET" "${OPT_TARGET_NAME};${doc_dir}/index.html" PARENT_SCOPE)
endfunction()

# Like rust_crate_auto, but this time it generates documentation using rust_doc.
#
# Optional arguments:
#
# ALL - Pass this to make this crate be built by default.
# DESTINATION dest - Where to place the compilation artifacts.
# TARGET_NAME target - Target name for the command to build this crate.
# DEPENDS depends - List of dependencies of this crate.
# OTHER_RUSTC_FLAGS flags - Other flags to pass to rustc.
# OTHER_RUSTDOC_FLAGS flags - Other flags to pass to rustdoc.
#
# This function sets two variables:
#
# ${target_name}_FULL_TARGET - This is what you would use as a set of dependencies
#                              for other targets when you want them to depend on the
#                              output of this target.
#
# ${target_name}_ARTIFACTS - The actual files generated by this command.
#                            You'd use this as a set of files to install/copy elsewhere.
function(rust_doc_auto local_root_file)
	cmake_parse_arguments("OPT" "ALL" "DESTINATION;TARGET_NAME" "DEPENDS;OTHER_RUSTC_FLAGS;OTHER_RUSTDOC_FLAGS" ${ARGN})

	if(NOT OPT_TARGET_NAME)
		set(OPT_TARGET_NAME DOC)
	endif()

	if(OPT_ALL)
		set(ALL_ARG "ALL")
	else()
		set(ALL_ARG "")
	endif()

	get_rust_deps(${local_root_file} crate_deps_list
	              OTHER_RUSTC_FLAGS ${OPT_OTHER_RUSTC_FLAGS})

	rust_doc("${local_root_file}"
	         ${ALL_ARG}
	         TARGET_NAME "${OPT_TARGET_NAME}"
	         DESTINATION "${OPT_DESTINATION}"
	         DEPENDS "${crate_deps_list};${OPT_DEPENDS}"
	         OTHER_RUSTC_FLAGS ${OPT_OTHER_RUSTC_FLAGS}
	         OTHER_RUSTDOC_FLAGS ${OPT_OTHER_RUSTDOC_FLAGS})
	set("${OPT_TARGET_NAME}_ARTIFACTS" "${${OPT_TARGET_NAME}_ARTIFACTS}" PARENT_SCOPE)
	set("${OPT_TARGET_NAME}_FULL_TARGET" "${${OPT_TARGET_NAME}_FULL_TARGET}" PARENT_SCOPE)
endfunction()

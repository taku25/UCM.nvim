{{COPYRIGHT_HEADER}}

#include "{{HEADER_INCLUDE_PATH}}"

// Sets default values
{{CLASS_PREFIX}}{{CLASS_NAME}}::{{CLASS_PREFIX}}{{CLASS_NAME}}()
{
 	// Set this character to call Tick() every frame.  You can turn this off to improve performance if you don't need it.
	PrimaryActorTick.bCanEverTick = true;

}

// Called when the game starts or when spawned
void {{CLASS_PREFIX}}{{CLASS_NAME}}::BeginPlay()
{
	Super::BeginPlay();
	
}

// Called every frame
void {{CLASS_PREFIX}}{{CLASS_NAME}}::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

}

// Called to bind functionality to input
void {{CLASS_PREFIX}}{{CLASS_NAME}}::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);

}

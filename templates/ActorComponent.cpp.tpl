{{COPYRIGHT_HEADER}}

#include "{{CLASS_NAME}}.h"

// Sets default values for this component's properties
{{CLASS_PREFIX}}{{CLASS_NAME}}::{{CLASS_PREFIX}}{{CLASS_NAME}}()
{
	// Set this component to be initialized when the game starts, and to be ticked every frame.  You can turn these features
	// off to improve performance if you don't need them.
	PrimaryComponentTick.bCanEverTick = true;

	// ...
}


// Called when the game starts
void {{CLASS_PREFIX}}{{CLASS_NAME}}::BeginPlay()
{
	Super::BeginPlay();

	// ...
	
}


// Called every frame
void {{CLASS_PREFIX}}{{CLASS_NAME}}::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

	// ...
}
